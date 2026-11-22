#!/usr/bin/env bash
set -euo pipefail
project=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
export SFOS_WORK=${SFOS_WORK:-/home/bird/data/tmp/sfos-aarch64}
export TMPDIR="$SFOS_WORK/build"
export TMP="$TMPDIR"
export TEMP="$TMPDIR"
mkdir -p "$SFOS_WORK"/{source,downloads,build,cache,logs,tools} "$project/dist"
exec 9>"$SFOS_WORK/build.lock"
flock -n 9
for command in git python3 aarch64-linux-gnu-gcc lxc-usernsexec unshare rsync mkfs.ext4 img2simg depmod modprobe patchelf rpmbuild zstd; do
    command -v "$command" >/dev/null
done
python3 "$project/scripts/download-inputs.py" "$project" "$SFOS_WORK" | tee "$SFOS_WORK/logs/downloads.log"
if [[ ! -f "$SFOS_WORK/build/kernel.complete" ]] || ! cmp -s "$project/config/kernel-nabu.config" "$SFOS_WORK/build/kernel-nabu.config"; then
    if [[ ${SFOS_KERNEL_RAM:-1} == 1 ]]; then
        bash "$project/scripts/namespace.sh" bash "$project/scripts/build-kernel-ram.sh" "$project" \
            2>&1 | tee "$SFOS_WORK/logs/kernel-ram-build.log"
    else
        bash "$project/scripts/build-kernel.sh" 2>&1 | tee "$SFOS_WORK/logs/kernel-build.log"
        touch "$SFOS_WORK/build/kernel.complete"
    fi
    cp "$project/config/kernel-nabu.config" "$SFOS_WORK/build/kernel-nabu.config"
fi
bash "$project/scripts/namespace.sh" bash "$project/scripts/build-native-rootfs.sh" "$project" "$SFOS_WORK" \
    2>&1 | tee "$SFOS_WORK/logs/rootfs-build.log"
bash "$project/scripts/namespace.sh" bash "$project/scripts/build-images.sh" "$project" "$SFOS_WORK" \
    2>&1 | tee "$SFOS_WORK/logs/image-build.log"
