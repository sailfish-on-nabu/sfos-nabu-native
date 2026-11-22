#!/usr/bin/env bash
set -euo pipefail

build_user=$(id -un)
build_uid=$(id -u)
build_gid=$(id -g)
uid_start=$(awk -F: -v user="$build_user" '$1 == user && $3 >= 65536 {print $2; exit}' /etc/subuid)
gid_start=$(awk -F: -v user="$build_user" '$1 == user && $3 >= 65536 {print $2; exit}' /etc/subgid)

if [[ -z "$uid_start" || -z "$gid_start" ]]; then
    echo "The build account needs at least 65536 subordinate UIDs and GIDs." >&2
    exit 1
fi

# Sailfish reserves UIDs 100000 and 500000 for its device and AppSupport users.
exec lxc-usernsexec \
    -m "u:0:$build_uid:1" \
    -m "u:1:$uid_start:65534" \
    -m "u:100000:$((uid_start + 65534)):1" \
    -m "u:500000:$((uid_start + 65535)):1" \
    -m "g:0:$build_gid:1" \
    -m "g:1:$gid_start:65534" \
    -m "g:100000:$((gid_start + 65534)):1" \
    -m "g:500000:$((gid_start + 65535)):1" \
    -- unshare --mount --pid --fork "$@"
