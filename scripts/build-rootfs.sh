#!/usr/bin/env bash
set -euo pipefail
project=$1
work=$2
image_version=$(cat "$project/config/image-version")
host="$work/build/ubuntu-root"
guest="$work/build/sailfish-root"
original=/home/bird/data/hadk_18.1/SailfishOScommunity-release-5.3.0.15-nabu-alpha1
mkdir -p "$host" "$guest"
if [[ ! -f "$work/build/ubuntu-base.complete" ]]; then
    tar --numeric-owner --exclude='./dev/*' -xpf "$work/downloads/ubuntu-base-24.04.5-base-arm64.tar.gz" -C "$host"
    touch "$work/build/ubuntu-base.complete"
fi
if [[ ! -f "$work/build/sailfish-root.complete" ]]; then
    tar --numeric-owner --exclude='./dev/*' -xpf "$original/sfe-nabu-5.3.0.15-alpha1.tar.bz2" -C "$guest"
    touch "$work/build/sailfish-root.complete"
fi
if [[ ! -f "$work/build/ubuntu-packages.complete" ]]; then
    cp /etc/resolv.conf "$host/etc/resolv.conf"
    printf '#!/bin/sh\nexit 101\n' > "$host/usr/sbin/policy-rc.d"
    chmod 0755 "$host/usr/sbin/policy-rc.d"
    packages=(systemd-sysv systemd-container systemd-resolved systemd-timesyncd dbus network-manager nftables weston
        libgl1-mesa-dri libegl1 libgles2 mesa-utils alsa-utils pulseaudio sudo curl
        ca-certificates kmod iproute2 linux-firmware squashfs-tools zstd acl openssh-server busybox-static)
    unshare --mount bash "$project/scripts/in-namespace.sh" "$host" apt-get update
    unshare --mount bash "$project/scripts/in-namespace.sh" "$host" \
        apt-get --print-uris --yes --no-install-recommends install "${packages[@]}" > "$work/logs/apt-download-uris.txt"
    python3 "$project/scripts/download-apt.py" "$work/logs/apt-download-uris.txt" "$host/var/cache/apt/archives"
    unshare --mount bash "$project/scripts/in-namespace.sh" "$host" \
        /usr/bin/env DEBIAN_FRONTEND=noninteractive apt-get --no-download --yes --no-install-recommends install "${packages[@]}"
    touch "$work/build/ubuntu-packages.complete"
fi

rsync -a "$project/overlay/ubuntu/" "$host/"
rsync -a "$project/overlay/sailfish/" "$guest/"
rm -f "$guest/var/lib/environment/compositor/90-live.conf" "$guest/var/lib/environment/nemo/90-mainline.conf"
mkdir -p "$host/opt/weston9" "$host/usr/lib/modules" "$guest/usr/lib/sailfish-live"
dpkg-deb -x "$work/downloads/weston_9.0.0-4ubuntu1_arm64.deb" "$host/opt/weston9"
dpkg-deb -x "$work/downloads/libweston-9-0_9.0.0-4ubuntu1_arm64.deb" "$host/opt/weston9"
ln -sfn /opt/weston9/usr/lib/aarch64-linux-gnu/libweston-9 "$host/usr/lib/aarch64-linux-gnu/libweston-9"
rsync -aH "$work/build/kernel-modules/lib/modules/" "$host/usr/lib/modules/"
find "$host/usr/lib/modules" -maxdepth 2 -name build -type l -delete
tar -xpf "$work/downloads/nabu-firmware.pkg.tar.xz" -C "$host" usr/lib/firmware usr/share/qcom
mkdir -p "$host/usr/share/alsa/ucm2/Xiaomi/nabu" "$host/usr/share/alsa/ucm2/conf.d/sm8150"
cp "$project/inputs/alsa/HiFi.conf" "$project/inputs/alsa/Speaker.conf" "$host/usr/share/alsa/ucm2/Xiaomi/nabu/"
cp "$project/inputs/alsa/sm8150.conf" "$host/usr/share/alsa/ucm2/conf.d/sm8150/"
mkdir -p "$guest/usr/share/alsa"
rsync -a "$host/usr/share/alsa/ucm2/" "$guest/usr/share/alsa/ucm2/"
python3 "$project/scripts/copy-native-mesa.py" "$host" "$guest"
bash "$project/scripts/build-native-runtime.sh" "$project" "$work"
cp "$project/scripts/remove-android-packages.sh" "$guest/tmp/remove-android-packages.sh"
cp "$project/config/excluded-packages.txt" "$guest/tmp/excluded-packages.txt"
cp "$project/dist/sfos-mainline-runtime-$image_version-1.aarch64.rpm" "$guest/tmp/"
unshare --mount bash "$project/scripts/in-namespace.sh" "$guest" \
    /bin/bash /tmp/remove-android-packages.sh /tmp/excluded-packages.txt \
    "/tmp/sfos-mainline-runtime-$image_version-1.aarch64.rpm"
rm -f "$guest/tmp/remove-android-packages.sh" "$guest/tmp/excluded-packages.txt" \
    "$guest/tmp/sfos-mainline-runtime-$image_version-1.aarch64.rpm"
rsync -a "$project/overlay/runtime/" "$guest/"
aarch64-linux-gnu-gcc -shared -fPIC -nostdlib -Wall -Wextra -Werror \
    "$project/src/wayland-parent.c" -Wl,--no-as-needed "$guest/usr/lib64/libwayland-client.so.0" \
    -o "$guest/usr/lib/sailfish-live/libwayland-parent.so"
host_audio_gid=$(awk -F: '$1 == "audio" {print $3}' "$host/etc/group")
host_render_gid=$(awk -F: '$1 == "render" {print $3}' "$host/etc/group")
cp "$project/scripts/configure-sailfish.sh" "$guest/tmp/configure-live.sh"
unshare --mount bash "$project/scripts/in-namespace.sh" "$guest" /bin/bash /tmp/configure-live.sh "$host_audio_gid" "$host_render_gid"
rm -f "$guest/tmp/configure-live.sh"
cp "$project/scripts/configure-ubuntu.sh" "$host/tmp/configure-live.sh"
unshare --mount bash "$project/scripts/in-namespace.sh" "$host" /bin/bash /tmp/configure-live.sh
rm -f "$host/tmp/configure-live.sh"
mkdir -p "$host/opt/sailfish/rootfs"
rsync -aHAX --delete --numeric-ids "$guest/" "$host/opt/sailfish/rootfs/"
python3 "$project/scripts/audit-packages.py" "$project/inputs/Jolla-5.3.0.15-nabu-aarch64.packages" \
    "$guest/etc/sailfish-live-packages.txt" "$project/dist/package-audit.json" \
    --exclude "$project/config/excluded-packages.txt" --native-package sfos-mainline-runtime.aarch64
cp "$host/etc/ubuntu-live-packages.tsv" "$project/dist/ubuntu-packages.tsv"
cp "$guest/etc/sailfish-live-packages.txt" "$project/dist/sailfish-packages.txt"
