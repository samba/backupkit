#!/bin/bash

set -euf -o pipefail

source /etc/backblaze.sh

HOSTNAME=$(hostname -f)
INCLUDES=${HOME}/.restic-files.txt
EXCLUDES=${HOME}/.restic-excludes.txt

if ! test -f ${INCLUDES}; then
    if test 0 -eq $UID; then
        INCLUDES=/etc/restic-files.txt
        EXCLUDES=/etc/restic-excludes.txt
    fi
fi

INTERACTIVE=false
test -t 1 && INTERACTIVE=true


TAGS="manual"
case $INTERACTIVE in
    false) TAGS="auto"
    ;;
esac

for i; do
case $i in
backup)
    test -r ${INCLUDES} && \
        restic backup \
            --exclude-caches=true \
            --exclude-file=${EXCLUDES} \
            --files-from=${INCLUDES} \
            --host=${HOSTNAME} \
            --tag=${TAGS}
    ;;
clean)

    restic forget -c --prune \
        --keep-daily=7 \
        --keep-weekly=3 \
        --keep-monthly=3 \
        --keep-hourly=12 \
        --host=${HOSTNAME} \
        --tag=$TAGS

    ;;
esac
done


