#!/usr/bin/env bash
set -euo pipefail
project=$(cd -- "$(dirname -- "$0")/.." && pwd)
image_version=$(cat "$project/config/image-version")
work=${SFOS_WORK:-/home/bird/data/tmp/sfos-aarch64}
disk="$work/build/nabu-installed-test.qcow2"
mkdir -p "$work/build"
base_hash=$(awk -v image="sailfish-$image_version-nabu-rootfs.img" '$2 == image {print $1}' "$project/dist/SHA256SUMS")
test -n "$base_hash"
if [[ -f "$disk" ]] && [[ ! -f "$disk.base-sha256" || $(cat "$disk.base-sha256") != "$base_hash" ]]; then
    echo "The disposable QEMU disk belongs to an older image. Remove $disk before testing the rebuilt rootfs." >&2
    exit 1
fi
if [[ ! -f "$disk" ]]; then
    qemu-img create -f qcow2 -F raw -b "$project/dist/sailfish-$image_version-nabu-rootfs.img" "$disk"
    qemu-img resize "$disk" +2G
    printf '%s\n' "$base_hash" > "$disk.base-sha256"
fi
exec qemu-system-aarch64 -machine virt,gic-version=3 -cpu max -smp 4 -m 4096 \
    -kernel "$project/dist/kernel/Image" -initrd "$project/dist/initramfs.cpio.gz" \
    -append 'console=ttyAMA0,115200 systemd.gpt_auto=no systemd.unified_cgroup_hierarchy=0 systemd.legacy_systemd_cgroup_controller=1 loglevel=6' \
    -drive "file=$disk,format=qcow2,if=none,id=root" -device virtio-blk-pci,drive=root \
    -netdev user,id=net,hostfwd=tcp:127.0.0.1:2227-:22 -device virtio-net-pci,netdev=net \
    -device virtio-gpu-pci -device virtio-keyboard-pci -device virtio-tablet-pci \
    -device virtio-rng-pci -display none -serial stdio \
    -qmp "unix:$work/build/nabu-installed-qmp.sock,server=on,wait=off"
