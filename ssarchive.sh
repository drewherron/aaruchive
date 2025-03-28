#!/bin/zsh

# Function to print usage and exit
usage() {
    echo "Backup Script - Backs up directories using rsync"
    echo ""
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -i, --input FILE    Text file with list of directories to back up (one per line)"
    echo "  -o, --output DIR    Directory where backups will be stored"
    echo "  -e, --exclude FILE  Optional: Text file with paths to exclude (one per line)"
    echo "  -h, --help          Display this help message"
    echo ""
    echo "Example:"
    echo "  $0 --input dirs.txt --output /mnt/backup --exclude exclude.txt"
    exit 1
}

# Default values
INPUT_FILE=""
OUTPUT_DIR=""
EXCLUDE_FILE=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -i|--input)
            INPUT_FILE="$2"
            shift 2
            ;;
        -o|--output)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        -e|--exclude)
            EXCLUDE_FILE="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

# Check if required arguments are provided
if [ -z "$INPUT_FILE" ] || [ -z "$OUTPUT_DIR" ]; then
    echo "Error: --input and --output are required."
    usage
fi

# Check if the input file exists
if [ ! -f "$INPUT_FILE" ]; then
    echo "Error: Input file '$INPUT_FILE' not found."
    exit 1
fi

# Check if output directory exists or can be created
if [ ! -d "$OUTPUT_DIR" ]; then
    mkdir -p "$OUTPUT_DIR" || { echo "Error: Cannot create output directory '$OUTPUT_DIR'."; exit 1; }
fi

# Get hostname
HOSTNAME=$HOST

# Convert output directory to absolute path
OUTPUT_DIR=$(cd "$OUTPUT_DIR" 2>/dev/null && pwd || echo "$OUTPUT_DIR")

# Create backup directory
BACKUP_DIR="$OUTPUT_DIR/$HOSTNAME"
mkdir -p "$BACKUP_DIR" || { echo "Error: Cannot create backup directory '$BACKUP_DIR'."; exit 1; }

echo "Creating backup in: $BACKUP_DIR"
echo "Reading directories from: $INPUT_FILE"

# Load exclusion list if provided
EXCLUSIONS=()
if [ -n "$EXCLUDE_FILE" ] && [ -f "$EXCLUDE_FILE" ]; then
    echo "Using exclusion list from: $EXCLUDE_FILE"
    while IFS= read -r EXCL || [[ -n "$EXCL" ]]; do
        # Skip empty lines and comments
        [[ -z "$EXCL" || "$EXCL" == \#* ]] && continue
        # Remove trailing slash if exists
        EXCL=${EXCL%/}
        EXCLUSIONS+=("$EXCL")
    done < "$EXCLUDE_FILE"
    echo "Loaded ${#EXCLUSIONS[@]} exclusion patterns"
fi

# Process each directory in the list
while IFS= read -r DIR || [[ -n "$DIR" ]]; do
    # Skip empty lines and comments
    [[ -z "$DIR" || "$DIR" == \#* ]] && continue
    
    # Strip trailing slash if exists
    DIR=${DIR%/}
    
    echo "Processing directory: $DIR"
    
    # Check if the directory exists
    if [ ! -d "$DIR" ]; then
        echo "Warning: Directory '$DIR' does not exist. Skipping."
        continue
    fi
    
    # Get the basename of the directory
    DIR_NAME=$(basename "$DIR")
    
    # Create the destination directory
    mkdir -p "$BACKUP_DIR/$DIR_NAME"
    
    # Convert current directory to absolute path
    DIR=$(cd "$DIR" 2>/dev/null && pwd || echo "$DIR")
    
    # Check if this directory IS the backup directory (direct match)
    if [[ "$DIR" == "$BACKUP_DIR" || "$DIR" == "$OUTPUT_DIR" ]]; then
        echo "WARNING: Directory '$DIR' is the backup destination."
        echo "This would cause infinite recursion. Skipping this directory."
        continue
    fi
    
    # Create a temporary exclude file specific to this directory
    TEMP_EXCLUDE_FILE=$(mktemp)
    
    # Process exclusions for this directory
    if [ ${#EXCLUSIONS[@]} -gt 0 ]; then
        echo "Finding applicable exclusions for $DIR/"
        for EXCL in "${EXCLUSIONS[@]}"; do
            # Check if this exclusion applies to the current directory
            if [[ "$EXCL" == "$DIR"/* ]]; then
                # Convert to a path relative to the source directory
                REL_EXCL="${EXCL#$DIR/}"
                echo "  Excluding: $REL_EXCL"
                echo "$REL_EXCL" >> "$TEMP_EXCLUDE_FILE"
            fi
        done
    fi
    
    # If the backup directory is inside this directory, add it to exclusions
    if [[ "$BACKUP_DIR" == "$DIR"/* ]]; then
        # Get the relative path from the source to the backup dir
        REL_BACKUP="${BACKUP_DIR#$DIR/}"
        echo "WARNING: The backup destination is inside this source directory."
        echo "  Auto-excluding: $REL_BACKUP"
        echo "$REL_BACKUP" >> "$TEMP_EXCLUDE_FILE"
    fi
    
    # Run rsync with exclusion file if there are applicable exclusions
    echo "Backing up $DIR/ to $BACKUP_DIR/$DIR_NAME/"
    
    if [ -s "$TEMP_EXCLUDE_FILE" ]; then
        echo "Using exclusion file with $(wc -l < "$TEMP_EXCLUDE_FILE") patterns"
        rsync -av --exclude-from="$TEMP_EXCLUDE_FILE" "$DIR/" "$BACKUP_DIR/$DIR_NAME/"
    else
        echo "No applicable exclusions for this directory"
        rsync -av "$DIR/" "$BACKUP_DIR/$DIR_NAME/"
    fi
    
    # Check if rsync was successful
    if [ $? -eq 0 ]; then
        echo "Successfully backed up: $DIR/"
    else
        echo "Error backing up: $DIR/"
    fi
    
    # Remove the temporary file
    rm -f "$TEMP_EXCLUDE_FILE"
    
    echo "----------------------------------------"
    
done < "$INPUT_FILE"

echo "Backup completed to: $BACKUP_DIR"
echo "Directories backed up:"
ls -la "$BACKUP_DIR"
