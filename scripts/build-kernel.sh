#!/usr/bin/env bash
set -euo pipefail

source_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
work_directory=${SFOS_WORK:-/home/bird/data/tmp/sfos-aarch64}
kernel_source="$source_directory/source/linux"
kernel_output="$work_directory/build/kernel"
export TMPDIR=${TMPDIR:-"$work_directory/build"}
mkdir -p "$work_directory"/{source,build,logs} "$source_directory/dist/kernel"

if [[ ! -d "$kernel_source/.git" ]]; then
    git clone --depth=1 --single-branch --branch native \
        https://github.com/sailfish-on-nabu/linux-nabu-native.git "$kernel_source"
fi

git -C "$kernel_source" rev-parse HEAD > "$source_directory/inputs/kernel-commit.txt"
git -C "$kernel_source" rev-parse --is-shallow-repository > "$source_directory/inputs/kernel-shallow.txt"
mkdir -p "$kernel_output"
if [[ ! -f "$kernel_output/.config" ]]; then
    make -C "$kernel_source" O="$kernel_output" ARCH=arm64 \
        CROSS_COMPILE=aarch64-linux-gnu- sm8150_defconfig
fi
(
    cd "$kernel_output"
    "$kernel_source/scripts/kconfig/merge_config.sh" -m -O "$kernel_output" \
        "$kernel_output/.config" "$source_directory/config/kernel-nabu.config"
)
make -C "$kernel_source" O="$kernel_output" ARCH=arm64 \
    CROSS_COMPILE=aarch64-linux-gnu- olddefconfig

# Match the PKGBUILD package release while retaining sm8150_defconfig.
printf '%s\n' '-0' > "$kernel_output/localversion.10-pkgrel"
export GIT_DIR=/dev/null
jobs=${SFOS_JOBS:-8}
make -C "$kernel_source" O="$kernel_output" ARCH=arm64 \
    CROSS_COMPILE=aarch64-linux-gnu- -j"$jobs" Image Image.gz modules
make -C "$kernel_source" O="$kernel_output" ARCH=arm64 \
    CROSS_COMPILE=aarch64-linux-gnu- -j"$jobs" DTC_FLAGS=-@ dtbs

kernel_version=$(cat "$kernel_output/include/config/kernel.release")
printf '%s\n' "$kernel_version" > "$source_directory/dist/kernel/kernel-release.txt"
cp "$kernel_output/arch/arm64/boot/Image" "$source_directory/dist/kernel/Image"
cp "$kernel_output/arch/arm64/boot/Image.gz" "$source_directory/dist/kernel/Image.gz"
cp "$kernel_output/arch/arm64/boot/dts/qcom/sm8150-xiaomi-nabu.dtb" \
    "$source_directory/dist/kernel/sm8150-xiaomi-nabu.dtb"
cp "$kernel_output/.config" "$source_directory/dist/kernel/config-$kernel_version"

rm -rf "$work_directory/build/kernel-modules"
mkdir -p "$work_directory/build/kernel-modules"
make -C "$kernel_source" O="$kernel_output" ARCH=arm64 \
    CROSS_COMPILE=aarch64-linux-gnu- \
    INSTALL_MOD_PATH="$work_directory/build/kernel-modules" \
    INSTALL_MOD_STRIP=1 DEPMOD=/bin/true modules_install
depmod -b "$work_directory/build/kernel-modules" "$kernel_version"
cp "$source_directory/config/kernel-nabu.config" "$work_directory/build/kernel-nabu.config"
touch "$work_directory/build/kernel.complete"
