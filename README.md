# ssarchive

A simple directory backup tool using rsync. It's basically just a wrapper for rsync that takes in lists of directories to include and exclude. I made this to simplify occasional backups to an external drive, or to consolidate backups into a single cron job.

`ss` stands for "stupid simple" because it's almost stupid for this to have its own repo. Almost.

## Installation

```bash
git clone https://github.com/drewherron/ssarchive.git
chmod +x ssarchive.sh
```

## Usage

### Basic Usage

```bash
./ssarchive.sh --input dir_list.txt --output /path/to/backups
```

### With Pattern Exclusions

```bash
./ssarchive.sh --input dir_list.txt --output /path/to/backups --exclude patterns.txt
```

### With Path Exclusions

```bash
./ssarchive.sh --input dir_list.txt --output /path/to/backups --path-exclude paths.txt
```

### With Both Types of Exclusions

```bash
./ssarchive.sh --input dir_list.txt --output /path/to/backups --exclude patterns.txt --path-exclude paths.txt
```

### Command Line Options

```
Options:
  -i, --input FILE      Text file with list of directories to back up (one per line)
  -o, --output DIR      Directory where backups will be stored
  -e, --exclude FILE    Optional: Text file with exclusion patterns (one per line)
  -p, --path-exclude FILE  Optional: Text file with absolute paths to exclude
  -h, --help            Display help message
```

### Directory List Format

Create a text file with one directory path per line:

```
/home/user/Documents
/home/user/Pictures
/var/www
```

### Pattern Exclusion Format

Create a text file with rsync exclusion patterns (one per line):

```
venv
__pycache__
*.pyc
.git/
node_modules/
*.log
```

Patterns support:
- Simple names: `venv` excludes all dirs/files named 'venv'
- Wildcards: `*.log` excludes all log files
- Directories: `node_modules/` excludes all node_modules directories
- Paths: `/specific/path` excludes from root of each source
- Comments: lines beginning with `#` are ignored

### Path Exclusion Format

Create a text file with full absolute paths to exclude:

```
/home/user/Documents/temp
/home/user/Pictures/large-files
/var/www/cache
```

### As a Cron Job

Add to crontab to run daily:

```
0 2 * * * /path/to/ssarchive.sh -i /path/to/dir_list.txt -o /path/to/backups -e /path/to/patterns.txt
```

## How It Works

ssarchive processes backups in several steps:

1. **Directory Reading**: Reads the source directories list, processing each directory separately while preserving its original name in the backup location.

2. **Exclusion Processing**: 
   - **Pattern exclusions**: Passed directly to rsync via `--exclude-from` for efficient pattern matching across all files
   - **Path exclusions**: Processed per-directory to convert absolute paths to relative paths that rsync can understand
   - Creates temporary exclusion files for path-based exclusions when needed

3. **Rsync Configuration**: Uses rsync with these options:
   - `-a` (archive): Preserves permissions, ownership, timestamps, and other attributes
   - `-v` (verbose): Shows detailed progress information
   - No `--delete` option: Files in the destination that no longer exist in the source are preserved
   
4. **Backup Structure**: Each source directory gets its own subdirectory in the backup location, maintaining its original name (e.g., `/backups/Documents/`).

This approach makes it easy to back up multiple directories to a single location while excluding files by pattern or specific paths, and is particularly useful for recurring backups to external drives or network storage.

Pull requests are welcome!
