#!/bin/bash

# A configuration wrapper around restic


set -euf -o pipefail

test -t 1
INTERACTIVE=$?

HOSTNAME=$(hostname -f)


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

run_profile () {
    test -f "${RESTIC_PASSWORD_FILE}" || fail 2 "Required environment variable: RESTIC_PASSWORD_FILE"
    test -z "${RESTIC_REPOSITORY}" && fail 3 "Required environment variable: RESTIC_REPOSITORY"

    local include_file=$(mktemp /tmp/restic.include.XXXXXX)
    local exclude_file=$(mktemp /tmp/restic.exclude.XXXXXX)
    local name=$(grep -oE '^profile\s+([^#]*)$' $1 | cut -f 2- -d ' ')
    local maxsize=$(grep -oE '^maxsize\s+([^#]*)$' $1 | cut -f 2 -d ' ')
    local repository=$(grep -oE '^repository\s+([^#]*)$' $1 | cut -f 2- -d ' ')

    grep -v '^#' $1 | envsubst | read_includes > ${include_file}
    grep -v '^#' $1 | envsubst | read_excludes > ${exclude_file}

    restic backup \
        --repo=${repository:-${RESTIC_REPOSITORY}} \
        --exclude-caches=true \
        --exclude-larger-than=${maxsize:-8G} \
        --files-from=${include_file} \
        --exclude-file=${exclude_file} \
        --host=${HOSTNAME} \
        --tag=${name:-$1} \
        --tag=$(test 0 -eq $INTERACTIVE && echo 'interactive' || echo 'automatic')


    result=$?

    rm ${include_file} ${exclude_file}

    return $result
}

clean_profile () {
    local name=$(grep -oE '^profile\s+([^#]*)$' $1 | cut -f 2- -d ' ')
    local repository=$(grep -oE '^repository\s+([^#]*)$' $1 | cut -f 2- -d ' ' )
    local hourly=$(grep '^hourly\s+(\d+).*$' $1 | cut -f 2 -d ' ')
    local daily=$(grep '^daily\s+(\d+).*$' $1 | cut -f 2 -d ' ')
    local weekly=$(grep '^weekly\s+(\d+).*$' $1 | cut -f 2 -d ' ')
    local monthly=$(grep '^monthly\s+(\d+).*$' $1 | cut -f 2 -d ' ')
    local yearly=$(grep '^yearly\s+(\d+).*$' $1 | cut -f 2 -d ' ')

    restic forget --prune \
        --repo=${repository:-${RESTIC_REPOSITORY}} \
        --keep-daily=${daily:-7} \
        --keep-weekly=${weekly:-4} \
        --keep-monthly=${monthly:-6} \
        --keep-yearly=${yearly:-3} \
        --host=${HOSTNAME} \
        --tag=${name:-$1}
}

main () {
    local verb=$1; shift;

    local profile="${HOME}/.restic.profile.txt";

    while getopts ":p:" OPT; do
        case $OPT in
            p) profile="${OPTARG}";;
        esac
    done


    case $verb in
        init)
            test -r ${profile} || fail 1 "Invalid profile: ${profile}";
            init_profile ${profile};
            ;;
        backup)
            test -r ${profile} || fail 1 "Invalid profile: ${profile}";
            run_profile ${profile};
            ;;
        clean)
            test -r ${profile} || fail 1 "Invalid profile: ${profile}";
            clean_profile ${profile};
            ;;
        size)
            test -r ${profile} || fail 1 "Invalid profile: ${profile}";
            grep -v '^#' ${profile} | envsubst | read_includes | xargs du -shc;
            ;;
    esac

}

main "${@}"


