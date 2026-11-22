#!/usr/bin/env bash
set -euo pipefail
project=$(cd -- "$(dirname -- "$0")/../.." && pwd)
work=${SFOS_WORK:-/home/bird/data/tmp/sfos-aarch64}
source_dir="$project/source/linux"
output="$work/build/kernel"
saved="$work/build/doubletap-kernel-disk-cache"
artifacts="${NABU_DT2W_ARTIFACTS:-$project/work/logs/doubletap-20261121/artifacts}"
mkdir -p "$saved" "$artifacts"
mount --bind "$output" "$saved"
mount -t tmpfs -o size=12G,mode=0755 tmpfs "$output"
rsync -a --exclude='*.ko' --exclude='/vmlinux.o' --exclude='/vmlinux.a' "$saved/" "$output/"
export GIT_DIR=/dev/null
export TMPDIR="$output"
make -C "$source_dir" O="$output" ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j12 DTC_FLAGS=-@ Image Image.gz qcom/sm8150-xiaomi-nabu.dtb
make -C "$source_dir" O="$output" ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j4 drivers/input/touchscreen/nt36523/nt36523_ts.ko
cp "$output/arch/arm64/boot/Image.gz" "$artifacts/Image.gz"
cp "$output/arch/arm64/boot/dts/qcom/sm8150-xiaomi-nabu.dtb" "$artifacts/"
aarch64-linux-gnu-strip --strip-debug -o "$artifacts/nt36523_ts.ko" "$output/drivers/input/touchscreen/nt36523/nt36523_ts.ko"
cp "$output/.config" "$artifacts/kernel.config"
cp "$output/include/config/kernel.release" "$artifacts/kernel.release"
cp "$output/System.map" "$artifacts/System.map"
(cd "$artifacts" && sha256sum Image.gz sm8150-xiaomi-nabu.dtb nt36523_ts.ko > SHA256SUMS)
echo 'Double-tap kernel artifacts staged successfully.'
