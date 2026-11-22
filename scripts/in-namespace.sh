#!/usr/bin/env bash
set -euo pipefail

root_directory=$1
shift

mkdir -p "$root_directory"/{dev,proc,sys,run,tmp}
mount --rbind /dev "$root_directory/dev"
mount --make-rslave "$root_directory/dev"
mount -t proc proc "$root_directory/proc"
mount --rbind /sys "$root_directory/sys"
mount --make-rslave "$root_directory/sys"
mount -t tmpfs tmpfs "$root_directory/run"
export TMPDIR=/tmp
export TMP=/tmp
export TEMP=/tmp
export LC_ALL=C
exec chroot "$root_directory" "$@"
