#!/usr/bin/env bash
set -euo pipefail
project=$1
work=$2
image_version=$(cat "$project/config/image-version")
root="$work/build/native-root"
dist="$project/dist"
mkdir -p "$dist"
bash "$project/scripts/build-boot-images.sh" "$project" "$work"

image="$dist/sailfish-$image_version-nabu-rootfs.img"
payload_size=$(du -sb "$root" | cut -f1)
image_size=$(( (payload_size + 2147483648 + 1073741823) / 1073741824 * 1073741824 ))
truncate -s "$image_size" "$image.partial"
mkfs.ext4 -F -b 4096 -L SFOS_ROOT -m 1 \
    -E lazy_itable_init=0,lazy_journal_init=0 -d "$root" "$image.partial"
e2fsck -fn "$image.partial"
mv "$image.partial" "$image"
img2simg "$image" "$dist/sailfish-$image_version-nabu-rootfs.sparse.img.partial" 4096
mv "$dist/sailfish-$image_version-nabu-rootfs.sparse.img.partial" "$dist/sailfish-$image_version-nabu-rootfs.sparse.img"
cd "$dist"
sha256sum sailfish-"$image_version"-*.img sfos-mainline-runtime-"$image_version"-*.aarch64.rpm sfos-nabu-native-"$image_version"-*.aarch64.rpm initramfs.cpio.gz \
    kernel/Image kernel/Image.gz kernel/sm8150-xiaomi-nabu.dtb > SHA256SUMS
