#!/usr/bin/env bash
set -euo pipefail
project=$1
work=$2
image_version=$(cat "$project/config/image-version")
dist="$project/dist"
python3 "$project/scripts/build-initramfs.py" "$project" "$work"
cmdline='console=ttyMSM0,115200n8 console=tty0 earlycon fw_devlink=permissive acpi=off systemd.gpt_auto=no systemd.unified_cgroup_hierarchy=0 systemd.legacy_systemd_cgroup_controller=1 loop.max_part=8 loglevel=6'
printf '%s\n' "$cmdline" > "$dist/kernel/cmdline.txt"

# The nabu deviceinfo uses Android header v0 with an appended DTB.
cat "$dist/kernel/Image.gz" "$dist/kernel/sm8150-xiaomi-nabu.dtb" > "$work/build/Image.gz-dtb"
python3 "$project/scripts/mkbootimg.py" \
    --header_version 0 --pagesize 4096 --base 0x00000000 \
    --kernel_offset 0x00008000 --ramdisk_offset 0x01000000 \
    --second_offset 0x00f00000 --tags_offset 0x00000100 \
    --kernel "$work/build/Image.gz-dtb" --ramdisk "$dist/initramfs.cpio.gz" \
    --cmdline "$cmdline" --os_version 11.0.0 --os_patch_level 2024-02 \
    --output "$dist/sailfish-$image_version-nabu-boot.img"

# Keep a v3 pair for loaders configured to use the existing vendor_boot layout.
python3 "$project/scripts/mkbootimg.py" \
    --header_version 3 --kernel "$dist/kernel/Image.gz" --ramdisk "$dist/initramfs.cpio.gz" \
    --cmdline "$cmdline" --os_version 11.0.0 --os_patch_level 2024-02 \
    --output "$dist/sailfish-$image_version-nabu-boot-v3.img"
printf '\037\213\010\000\000\000\000\000\000\003\003\000\000\000\000\000\000\000\000\000' > "$work/build/vendor-ramdisk.gz"
python3 "$project/scripts/mkbootimg.py" \
    --header_version 3 --pagesize 4096 --base 0x00000000 \
    --kernel_offset 0x00008000 --ramdisk_offset 0x01000000 --tags_offset 0x00000100 \
    --dtb_offset 0x01f00000 --dtb "$dist/kernel/sm8150-xiaomi-nabu.dtb" \
    --vendor_ramdisk "$work/build/vendor-ramdisk.gz" --vendor_cmdline "$cmdline" \
    --vendor_boot "$dist/sailfish-$image_version-nabu-vendor_boot-v3.img"

