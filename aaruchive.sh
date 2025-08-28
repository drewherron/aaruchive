#!/bin/zsh

# Function to print usage and exit
usage() {
    echo "Backup Script - Backs up directories using rsync"
    echo ""
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -i, --input FILE      Text file with list of directories to back up (one per line)"
    echo "  -o, --output DIR      Directory where backups will be stored"
    echo "  -e, --exclude FILE    Optional: Text file with exclusion patterns (one per line)"
    echo "  -p, --path-exclude FILE  Optional: Text file with absolute paths to exclude"
    echo "  -s, --strip-prefix DIR   Optional: Remove this prefix from source paths in output"
    echo "  -d, --delete             Optional: Delete files from destination that don't exist in source"
    echo "  -h, --help            Display this help message"
    echo ""
    echo "Exclusion Patterns:"
    echo "  Pattern file supports rsync patterns:"
    echo "    - Simple names: 'venv' excludes all dirs/files named 'venv'"
    echo "    - Wildcards: '*.log' excludes all log files"
    echo "    - Directories: 'node_modules/' excludes all node_modules directories"
    echo "    - Paths: '/specific/path' excludes from root of each source"
    echo ""
    echo "Examples:"
    echo "  $0 --input dirs.txt --output /mnt/backup --exclude patterns.txt"
    echo "  $0 --input dirs.txt --output /mnt/backup --strip-prefix /media/user/drive"
    echo ""
    echo "Example patterns.txt:"
    echo "  venv"
    echo "  __pycache__"
    echo "  *.pyc"
    echo "  .git/"
    echo "  node_modules/"
    echo "  *.log"
    exit 1
}

# Default values
INPUT_FILE=""
OUTPUT_DIR=""
EXCLUDE_FILE=""
PATH_EXCLUDE_FILE=""
STRIP_PREFIX=""
USE_DELETE=false

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
        -p|--path-exclude)
            PATH_EXCLUDE_FILE="$2"
            shift 2
            ;;
        -s|--strip-prefix)
            STRIP_PREFIX="$2"
            shift 2
            ;;
        -d|--delete)
            USE_DELETE=true
            shift
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

# Convert output directory to absolute path if possible
OUTPUT_DIR=$(cd "$OUTPUT_DIR" 2>/dev/null && pwd || echo "$OUTPUT_DIR")

# Use output directory directly as backup directory
BACKUP_DIR="$OUTPUT_DIR"

echo "Creating backup in: $BACKUP_DIR"
echo "Reading directories from: $INPUT_FILE"

# Build rsync options
RSYNC_OPTS="-avi"

# Add delete option if specified
if [ "$USE_DELETE" = true ]; then
    RSYNC_OPTS="$RSYNC_OPTS --delete"
    echo "Using --delete: files not in source will be removed from backup"
fi

# Add pattern exclusions if provided
if [ -n "$EXCLUDE_FILE" ] && [ -f "$EXCLUDE_FILE" ]; then
    echo "Using exclusion patterns from: $EXCLUDE_FILE"
    # Count non-empty, non-comment lines
    PATTERN_COUNT=$(grep -v '^#' "$EXCLUDE_FILE" | grep -v '^[[:space:]]*$' | wc -l)
    echo "Loaded $PATTERN_COUNT exclusion patterns"
    RSYNC_OPTS="$RSYNC_OPTS --exclude-from=$EXCLUDE_FILE"
fi

# Arrays to store statistics for each directory
DIR_PATHS=()
ADDED_COUNTS=()
UPDATED_COUNTS=()
DELETED_COUNTS=()

# Load path-based exclusions if provided
PATH_EXCLUSIONS=()
if [ -n "$PATH_EXCLUDE_FILE" ] && [ -f "$PATH_EXCLUDE_FILE" ]; then
    echo "Using path exclusions from: $PATH_EXCLUDE_FILE"
    while IFS= read -r EXCL || [[ -n "$EXCL" ]]; do
        # Skip empty lines and comments
        [[ -z "$EXCL" || "$EXCL" == \#* ]] && continue
        # Remove trailing slash if exists
        EXCL=${EXCL%/}
        PATH_EXCLUSIONS+=("$EXCL")
    done < "$PATH_EXCLUDE_FILE"
    echo "Loaded ${#PATH_EXCLUSIONS[@]} path exclusion entries"
fi

# Process each directory in the list
while IFS= read -r DIR || [[ -n "$DIR" ]]; do
    # Skip empty lines and comments
    [[ -z "$DIR" || "$DIR" == \#* ]] && continue

    # Strip trailing slash if exists
    DIR=${DIR%/}

    # Convert to absolute path if possible
    if [ -d "$DIR" ]; then
        DIR=$(cd "$DIR" 2>/dev/null && pwd || echo "$DIR")
    fi

    echo "Processing directory: $DIR"

    # Check if the directory exists
    if [ ! -d "$DIR" ]; then
        echo "WARNING: Directory '$DIR' does not exist. Skipping."
        continue
    fi

    # Check if this directory IS the backup directory (direct match)
    if [[ "$DIR" == "$BACKUP_DIR" || "$DIR" == "$OUTPUT_DIR" ]]; then
        echo "WARNING: Directory '$DIR' is the backup destination."
        echo "This would cause infinite recursion. Skipping this directory."
        continue
    fi

    # Create path structure for backup - preserve full paths
    # Apply prefix stripping if specified
    if [ -n "$STRIP_PREFIX" ] && [[ "$DIR" == "$STRIP_PREFIX"* ]]; then
        # Remove the strip prefix from the beginning of the path
        STRIPPED_DIR="${DIR#$STRIP_PREFIX}"
        # Remove leading slash if present after stripping
        STRIPPED_DIR="${STRIPPED_DIR#/}"
        # If nothing left after stripping, use the basename
        if [ -z "$STRIPPED_DIR" ]; then
            STRIPPED_DIR="$(basename "$DIR")"
        fi
        REL_PATH="$STRIPPED_DIR"
        echo "Stripped prefix '$STRIP_PREFIX' from path"
    else
        # Remove leading slash to avoid absolute paths
        REL_PATH="${DIR#/}"
    fi
    DEST_DIR="$BACKUP_DIR/$REL_PATH"

    echo "Destination: $DEST_DIR"

    # Create the destination directory
    mkdir -p "$DEST_DIR" || {
        echo "Error: Cannot create destination directory '$DEST_DIR'."
        continue
    }

    # Build directory-specific rsync options
    DIR_RSYNC_OPTS="$RSYNC_OPTS"

    # Create a temporary exclude file for path-specific exclusions
    TEMP_EXCLUDE_FILE=""
    if [ ${#PATH_EXCLUSIONS[@]} -gt 0 ]; then
        TEMP_EXCLUDE_FILE=$(mktemp)
        for EXCL in "${PATH_EXCLUSIONS[@]}"; do
            # Check if this exclusion applies to the current directory
            if [[ "$EXCL" == "$DIR"/* ]]; then
                # Convert to a path relative to the source directory
                REL_EXCL="${EXCL#$DIR/}"
                echo "  Path exclusion: $REL_EXCL"
                echo "$REL_EXCL" >> "$TEMP_EXCLUDE_FILE"
            fi
        done

        if [ -s "$TEMP_EXCLUDE_FILE" ]; then
            DIR_RSYNC_OPTS="$DIR_RSYNC_OPTS --exclude-from=$TEMP_EXCLUDE_FILE"
        fi
    fi

    # If the backup directory is inside this directory, exclude it
    if [[ "$BACKUP_DIR" == "$DIR"/* ]]; then
        # Get the relative path from the source to the backup dir
        REL_BACKUP="${BACKUP_DIR#$DIR/}"
        echo "WARNING: The backup destination is inside this source directory."
        echo "  Auto-excluding: $REL_BACKUP"
        DIR_RSYNC_OPTS="$DIR_RSYNC_OPTS --exclude=$REL_BACKUP"
    fi

    # Run rsync
    echo "Backing up $DIR/ to $DEST_DIR/"
    if [ -n "$EXCLUDE_FILE" ] && [ -f "$EXCLUDE_FILE" ]; then
        echo "Applying global exclusion patterns"
    fi

    # Create temporary file to capture rsync output
    RSYNC_OUTPUT=$(mktemp)
    
    eval rsync $DIR_RSYNC_OPTS "$DIR/" "$DEST_DIR/" | tee "$RSYNC_OUTPUT"

    # Check if rsync was successful
    if [ $? -eq 0 ]; then
        echo "Successfully backed up: $DIR/"
        
        # Parse rsync output to count operations
        ADDED=0
        UPDATED=0
        DELETED=0
        
        while IFS= read -r line; do
            if [[ "$line" == "*deleting "* ]]; then
                ((DELETED++))
            elif [[ "$line" =~ ^\>f\+\+\+\+\+\+\+\+\+ ]]; then
                ((ADDED++))
            elif [[ "$line" =~ ^\>f\.[st].* ]] || [[ "$line" =~ ^\>f[^+]+ ]]; then
                ((UPDATED++))
            fi
        done < "$RSYNC_OUTPUT"
        
        # Store statistics for this directory
        DIR_PATHS+=("$DIR")
        ADDED_COUNTS+=("$ADDED")
        UPDATED_COUNTS+=("$UPDATED")
        DELETED_COUNTS+=("$DELETED")
    else
        echo "Error backing up: $DIR/"
    fi
    
    # Clean up temporary rsync output file
    rm -f "$RSYNC_OUTPUT"

    # Remove the temporary file if created
    if [ -n "$TEMP_EXCLUDE_FILE" ]; then
        rm -f "$TEMP_EXCLUDE_FILE"
    fi

    echo "----------------------------------------"

done < "$INPUT_FILE"

echo "Backup completed to: $BACKUP_DIR"

# Display summary statistics
if [ ${#DIR_PATHS[@]} -gt 0 ]; then
    echo ""
    echo "Summary:"
    for ((i=0; i<${#DIR_PATHS[@]}; i++)); do
        echo "${DIR_PATHS[$i]}"
        printf "  Added: %8s       Updated: %8s       Deleted: %8s\n" "${ADDED_COUNTS[$i]}" "${UPDATED_COUNTS[$i]}" "${DELETED_COUNTS[$i]}"
    done
fi

echo "Directories backed up:"
ls -la "$BACKUP_DIR"
