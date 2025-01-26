#!/bin/bash

set -euf -o pipefail

fail () {
    err=$1; shift;
    echo "${@}" >&2
    exit $err
}


INTERACTIVE=1
test -t 1 && INTERACTIVE=0

print_help () {
cat <<EOF
Usage: $0 <verb> <profile>

Restic backup helper. Loads static configuration for easier scheduled backup.

A "verb" would be:

- init         prepare a repository (don't do this twice)
- backup       perform a snapshot backup into the repository
- clean        remove outdated snapshots
- snapshots    list snapshots in the repository
- size         calculate size of the included files on local storage
- genconf      generate a new backup profile configuration

Generally "profile" refers to the file path of the configuration file.
In the case of "genconf", profile is the profile name prepopulated into the config template.


Typical usage is to:
1. Generate a configuration profile:  $0 genconf [profile_name] > backup.profile.txt
2. Update the include paths for your needs.
3. Set up a cron job to perform scheduled backups.
4. Take the first backup snapshot:  $0 backup path/to/backup.profile.txt

An example configuration follows.
---
EOF

gen_config "example_config"

echo "---"

}

gen_config () {
cat <<EOF
# Restic backup profile configuration
# NOTE: ALL NAMED PARAMETERS ARE REQUIRED


profile    ${1:-UNNAMED_PROFILE}
repository <path>

# example
# repository b2:bucketname:backup/path/

# optional environment overrides
# export B2_ACCOUNT_ID=...
# export B2_ACCOUNT_KEY=...
# export RESTIC_PASSWORD_FILE=/path/to/passfile

# retention parameters
hourly     10
daily      7
weekly     4
monthly    6
yearly     2

# source data
maxsize      12G  # excludes files larger than this
include    \${HOME}/Documents/
include    \${Home}/Pictures/
exclude    **/cache/
exclude    **/*.bak
EOF
}

read_excludes () {
    grep -oE '^exclude\s+([^#]*)$' ${@} | cut -d ' ' -f 2-
}

read_includes () {
    grep -oE '^include\s+([^#]*)$' ${@} | cut -d ' ' -f 2-
}

cmd_backup () {

    local maxsize=$(grep -oE '^maxsize\s+([^#]*)$' $1 | cut -f 2 -d ' ')
    local packsize=$(grep -oE '^packsize\s+([^#]*)$' $1 | cut -f 2 -d ' ')

    restic backup \
        --repo=$(grep -oE '^repository\s+([^#]*)$' $1 | cut -f 2- -d ' ') \
        --exclude-caches=true \
        --exclude-larger-than=${maxsize:-8G} \
        --pack-size=${packsize:-128} \
        --files-from=<(cat $1 | envsubst | read_includes) \
        --exclude-file=<(cat $1 | envsubst | read_excludes) \
        --group-by hosts,paths,tags \
        --host=$(hostname) \
        --tag="$(grep -oE '^profile\s+([^#]*)$' $1 | tr -s ' ' |  cut -f 2- -d ' ')" \
        --tag=$(test 0 -eq $INTERACTIVE && echo 'interactive' || echo 'automatic')


}


cmd_init () {
    restic init -r $(grep -oE '^repository\s+([^#]*)$' $1 | cut -f 2- -d ' ')
}

cmd_clean () {
    restic forget --prune \
        --repo=$(grep -oE '^repository\s+([^#]*)$' $1 | cut -f 2- -d ' ') \
        --keep-hourly=$(grep -E '^hourly\s+([0-9]+).*$' $1 | tr -s ' ' | cut -f 2 -d ' ') \
        --keep-daily=$(grep -E '^daily\s+([0-9]+).*$' $1 | tr -s ' ' | cut -f 2 -d ' ') \
        --keep-weekly=$(grep -E '^weekly\s+([0-9]+).*$' $1 | tr -s ' ' | cut -f 2 -d ' ') \
        --keep-monthly=$(grep -E '^monthly\s+([0-9]+).*$' $1 | tr -s ' ' | cut -f 2 -d ' ') \
        --keep-yearly=$(grep -E '^yearly\s+([0-9]+).*$' $1 | tr -s ' ' | cut -f 2 -d ' ') \
        --host=$(hostname) \
        --tag="$(grep -oE '^profile\s+([^#]*)$' $1 | tr -s ' ' | cut -f 2- -d ' ')"

    restic cache --cleanup
}

cmd_snapshots ()  {
    restic snapshots -r $(grep -oE '^repository\s+([^#]*)$' $1 | cut -f 2- -d ' ') \
        --group-by hosts,paths,tags \
        --host=$(hostname) \
        --tag="$(grep -oE '^profile\s+([^#]*)$' $1 | tr -s ' ' | cut -f 2- -d ' ')"
}

cmd_size ()  {
    envsubst < $1 | read_includes | xargs du -shc
}

main () {
    command -v restic >/dev/null || fail 2 "Dependency missing: restic"
    command -v rclone >/dev/null || fail 2 "Dependency missing: rclone"

    case "$1" in
        genconf) gen_config "${2:-UNNAMED_PROFILE}"; return 0 ;;
        help) print_help; return 0 ;;
    esac

    local profile="${2:-profile_path}"

    test -f ${profile} || fail 1 "Invalid input profile path"

    eval $(grep -oE '^export\s+([^#]*)' ${profile})

    if test -n "${RESTIC_PASSWORD_FILE}" -a \! -f "${RESTIC_PASSWORD_FILE}" ; then
        fail 3 "Password file missing: ${RESTIC_PASSWORD_FILE}"
    fi

    case "$1" in
        init) cmd_init ${profile} ;;
        snapshots) cmd_snapshots  ${profile} ;;
        backup) cmd_backup  ${profile} ;;
        clean) cmd_clean ${profile} ;;
        size) cmd_size ${profile} ;;
    esac

}

main "${@}"

