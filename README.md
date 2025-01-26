# A [Restic][1] Backup Script

A convenience wrapper for Restic.

* Allows multiple repositories to be configured with distinct sources, retention patterns, and exclusions
* Configuration is human readable
* Relies strictly on shell script and common utilities (grep, cut, envsubst)

Assumes that both `restic` and `rclone` should be available (2025-01-25).

## Installation

* Copy this script into your `$PATH` somewhere. `/usr/local/bin/` is usually sensible.
* Define a backup profile like below: see `backup.sh genconf` for easy preparation.
* Configure backup jobs in your crontab like below.

### Usage

Please read the command-line help for overview, or the code in [backup.sh](./backup.sh).

Please review [the blog](./blog/2025-01-25-opendrive-restic-rclone.md) for setting up your rclone repository with restic.

### Cron jobs

```
# Backup jobs every 6 hours
10 */6 * * * bash path/to/backup.sh backup restic.media.txt

# Nightly cleanup jobs (retention is enforced here)
10 2 * * *   bash path/to/backup.sh clean restic.media.txt
```

## Profiles

A profile is a text file with a few directives to instruct the behavior of restic.

Note that **all keywords are required** (except for `export`) as of update 2025-01-25.

```
profile    <name>  # IMPORTANT: snapshots will be filtered on this
repository <path>  # Can be any repository restic supports (AWS S3, Backblaze B2, local path) - not quoted.

# bash-style exports are interpreted as inputs to restic environment.
export MY_REMOTE_KEY=abcde12345

# retention parameters -- how many of each to retain
hourly     <count>
daily      <count>
weekly     <count>
monthly    <count>
yearly     <count>

# source data
# multiple includes and excludes are allowed
maxsize    12G  # excludes files larger than this
include    ${HOME}/Documents/
include    ${HOME}/Pictures/
exclude    **/cache/
exclude    **/*.bak

```


[1]: https://restic.readthedocs.io/en/latest/index.html
