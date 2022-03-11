# A [Restic][1] Backup Script

Some convenience bits for my own usage.

* Allows multiple repositories to be configured with distinct sources, retention patterns, and exclusions
* Configuration is human readable
* Relies strictly on shell script and common utilities (grep, cut, envsubst)



## Installation

* Copy this script into your `$PATH` somewhere. `/usr/local/bin/` is usually sensible.
* Define a backup profile like below.
* Install backup jobs in your crontab like below.

### Cron jobs

```
# Backup jobs every 6 hours
10 */6 * * * bash ${HOME}/.bin/backup.sh backup -p /mnt/backup/config/restic.media.txt && df -h /mnt/backup/
30 */6 * * * bash ${HOME}/.bin/backup.sh backup -p /mnt/backup/config/restic.profile.txt && df -h /mnt/backup/

# Nightly cleanup jobs (retention is enforced here)
10 2 * * *   bash ${HOME}/.bin/backup.sh clean -p /mnt/backup/config/restic.media.txt && df -h /mnt/backup/
30 2 * * *   bash ${HOME}/.bin/backup.sh clean -p /mnt/backup/config/restic.profile.txt && df -h /mnt/backup/
```

## Profiles

A profile is a text file with a few directives to instruct the behavior of restic.

```
profile    <name>  # IMPORTANT: snapshots will be filtered on this
repository <path>  # Can be any repository restic supports (AWS S3, Backblaze B2, local path)

# retention parameters -- how many of each to retain
hourly     <count>
daily      <count>
weekly     <count>
monthly    <count>
yearly     <count>

# source data
# multiple includes and excludes are allowed
maxsize    12G  # excludes files larger than this
include    \${HOME}/Documents/
include    \${Home}/Pictures/
exclude    **/cache/
exclude    **/*.bak

```


[1]: https://restic.readthedocs.io/en/latest/index.html
