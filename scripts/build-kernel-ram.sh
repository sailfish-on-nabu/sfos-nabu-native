#!/usr/bin/env bash
set -euo pipefail
project=$1
work=${SFOS_WORK:-/home/bird/data/tmp/sfos-aarch64}
output="$work/build/kernel"
saved="$work/build/kernel-disk-cache"
mkdir -p "$output" "$saved"
mount --bind "$output" "$saved"
mount -t tmpfs -o "size=${SFOS_KERNEL_RAM_SIZE:-12G},mode=0755" tmpfs "$output"
rsync -a --exclude='*.ko' --exclude='/vmlinux.o' --exclude='/vmlinux.a' "$saved/" "$output/"
export TMPDIR="$output"
if ! bash "$project/scripts/build-kernel.sh"; then
    rsync -a "$output/" "$saved/"
    exit 1
fi
touch "$work/build/kernel.complete"
