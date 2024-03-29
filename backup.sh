#!/bin/bash

# A configuration wrapper around restic


set -euf -o pipefail

if test -t 1; then
    INTERACTIVE=0
else
    INTERACTIVE=1
fi


HOSTNAME=$(hostname -f)
LOCKFILE=/tmp/restic.backup.lock

export RESTIC_PASSWORD_FILE=${RESTIC_PASSWORD_FILE:-${HOME}/.restic_password}

print_help () {
cat <<EOF
Usage:  $0 [verb] -p <profile>

This is a convenience wrapper around restic.
It respects the restic environment variables.
If you do not specify a profile, it defaults to <${HOME}/.restic.profile.txt>.

A verb must be one of:
- init        prepares a repository for restic backups (don't do this twice)
- backup      performs a backup snapshot process into the repository
- clean       removes outdated snapshots from the repository
- snapshots   lists all snapshots in the repository
- size        calculates the size of live source directories (not accounting for excludes)

A profile is a text file of the following format:

   profile    <name>
   repository <path>

   # example
   # repository b2:bucketname:backup/path/

   # optional environment overrides
   export B2_ACCOUNT_ID=...
   export B2_ACCOUNT_KEY=...
   export RESTIC_PASSWORD_FILE=/path/to/passfile

   # retention parameters
   hourly     <count>
   daily      <count>
   weekly     <count>
   monthly    <count>
   yearly     <count>

   # source data
   maxsize      12G  # excludes files larger than this
   include    \${HOME}/Documents/
   include    \${Home}/Pictures/
   exclude    **/cache/
   exclude    **/*.bak

Environment:
   RESTIC_PASSWORD_FILE defaults to ${HOME}/.restic_password

EOF
}


fail () {
    err=$1; shift;
    echo "${@}" >&2
    exit $err
}

read_excludes () {
    grep -oE '^exclude\s+([^#]*)$' ${@} | cut -d ' ' -f 2-
}

read_includes () {
    grep -oE '^include\s+([^#]*)$' ${@} | cut -d ' ' -f 2-
}

init_profile () {
    local repository=$(grep -oE '^repository\s+([^#]*)$' $1 | cut -f 2- -d ' ')
    restic init -r ${repository:-${RESTIC_REPOSITORY}}
}

list_snapshots () {
    local repository=$(grep -oE '^repository\s+([^#]*)$' $1 | cut -f 2- -d ' ')
    restic snapshots -r ${repository:-${RESTIC_REPOSITORY}}
}

get_exports () {
    grep -oE '^export\s+([^#]*)' $1
}

get_lock () {
    test ! -f ${LOCKFILE} && echo $1 > ${LOCKFILE}
}

release_lock () {
    test -f ${LOCKFILE} && test $1 -eq $(head -n 1 ${LOCKFILE}) && rm -v ${LOCKFILE}
}

run_profile () {

    local name=$(grep -oE '^profile\s+([^#]*)$' $1 | cut -f 2- -d ' ')
    local maxsize=$(grep -oE '^maxsize\s+([^#]*)$' $1 | cut -f 2 -d ' ')
    local repository=$(grep -oE '^repository\s+([^#]*)$' $1 | cut -f 2- -d ' ')

    test -z "${repository:-${RESTIC_REPOSITORY}}" && fail 3 "Required environment variable: RESTIC_REPOSITORY"
    test -f "${RESTIC_PASSWORD_FILE}" || fail 2 "Required environment variable: RESTIC_PASSWORD_FILE"

    get_lock $$ || return 1

    restic backup \
        --repo=${repository:-${RESTIC_REPOSITORY}} \
        --exclude-caches=true \
        --exclude-larger-than=${maxsize:-8G} \
        --files-from=<(cat $1 | envsubst | read_includes) \
        --exclude-file=<(cat $1 | envsubst | read_excludes) \
        --host=${HOSTNAME} \
        --tag=${name:-$1} \
        --tag=$(test 0 -eq $INTERACTIVE && echo 'interactive' || echo 'automatic')

    release_lock $$

}

clean_profile () {
    local name=$(grep -oE '^profile\s+([^#]*)$' $1 | cut -f 2- -d ' ')
    local repository=$(grep -oE '^repository\s+([^#]*)$' $1 | cut -f 2- -d ' ' )
    local hourly=$(grep '^hourly\s+(\d+).*$' $1 | cut -f 2 -d ' ')
    local daily=$(grep '^daily\s+(\d+).*$' $1 | cut -f 2 -d ' ')
    local weekly=$(grep '^weekly\s+(\d+).*$' $1 | cut -f 2 -d ' ')
    local monthly=$(grep '^monthly\s+(\d+).*$' $1 | cut -f 2 -d ' ')
    local yearly=$(grep '^yearly\s+(\d+).*$' $1 | cut -f 2 -d ' ')

    get_lock $$ || return 1

    restic forget --prune \
        --repo=${repository:-${RESTIC_REPOSITORY}} \
        --keep-daily=${daily:-7} \
        --keep-weekly=${weekly:-4} \
        --keep-monthly=${monthly:-6} \
        --keep-yearly=${yearly:-3} \
        --host=${HOSTNAME} \
        --tag=${name:-$1}

    restic cache --cleanup

    release_lock $$
}

main () {
    local verb=$1; shift;

    local profile="${HOME}/.restic.profile.txt";

    while getopts ":p:" OPT; do
        case $OPT in
            p) profile="${OPTARG}";;
        esac
    done

    command -v restic || fail 2 "Could not find restic backup program."


    case $verb in
        init)
            test -r ${profile} || fail 1 "Invalid profile: ${profile}";
            eval "$(get_exports ${profile})";
            init_profile ${profile};
            ;;
        backup)
            test -r ${profile} || fail 1 "Invalid profile: ${profile}";
            eval "$(get_exports ${profile})";
            run_profile ${profile};
            ;;
        clean)
            test -r ${profile} || fail 1 "Invalid profile: ${profile}";
            eval "$(get_exports ${profile})";
            clean_profile ${profile};
            ;;
        snapshots)
            test -r ${profile} || fail 1 "Invalid profile: ${profile}";
            eval "$(get_exports ${profile})";
            list_snapshots ${profile};
            ;;
        size)
            test -r ${profile} || fail 1 "Invalid profile: ${profile}";
            grep -v '^#' ${profile} | envsubst | read_includes | xargs du -shc;
            ;;
        *)
            print_help;
            ;;
    esac

}

main "${@}"


