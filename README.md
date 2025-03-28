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

### With Exclusions

```bash
./ssarchive.sh --input dir_list.txt --output /path/to/backups --exclude exclude.txt
```

For both input and exclusion directories, you'll want to use the full path. I tried to switch to patterns for the exclusion list, and while it's simple with rsync alone, I just couldn't get it to work here.

### Command Line Options

```
Options:
  -i, --input FILE    Text file with list of directories to back up (one per line)
  -o, --output DIR    Directory where backups will be stored
  -e, --exclude FILE  Optional: Text file with paths to exclude (one per line)
  -h, --help          Display help message
```

### Directory List Format

Create a text file with one directory path per line:

```
/home/user/Documents
/home/user/Pictures
/var/www
```

### Exclusion List Format

Create a text file with full paths to exclude:

```
/home/user/Documents/temp
/home/user/Pictures/large-files
/var/www/cache
```

### As a Cron Job

Add to crontab to run daily:

```
0 2 * * * /path/to/ssarchive.sh -i /path/to/dir_list.txt -o /path/to/backups -e /path/to/exclude.txt
```

## How It Works

ssarchive processes backups in several steps:

1. **Directory Organization**: Creates a main backup directory with the local hostname (e.g., `/backups/hostname/`) to keep backups organized by machine.

2. **Directory Reading**: Reads the source directories list, processing each directory separately while preserving its original name in the backup location.

3. **Exclusion Processing**: 
   - Reads the exclusion file (if provided)
   - For each source directory, filters the exclusions to find only those relevant to that directory
   - Converts full exclusion paths to relative paths that rsync can understand
   - Creates temporary exclusion files tailored to each source directory

4. **Rsync Configuration**: Uses rsync with these options:
   - `-a` (archive): Preserves permissions, ownership, timestamps, and other attributes
   - `-v` (verbose): Shows detailed progress information
   - No `--delete` option: Files in the destination that no longer exist in the source are preserved
   
5. **Backup Structure**: Each source directory gets its own subdirectory in the backup location, maintaining its original name (e.g., `/backups/hostname/Documents/`).

This approach makes it easy to back up multiple directories to a single location while excluding specific subdirectories, and is particularly useful for recurring backups to external drives or network storage.

Pull requests are welcome, especially if you can figure out how to use patterns instead of paths in the exclusion list.
