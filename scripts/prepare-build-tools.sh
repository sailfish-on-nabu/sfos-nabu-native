#!/usr/bin/env bash
set -euo pipefail
project=$1
work=$2
host="$work/build/ubuntu-root"
mkdir -p "$host"
if [[ ! -f "$work/build/ubuntu-base.complete" ]]; then
    tar --numeric-owner --exclude='./dev/*' -xpf "$work/downloads/ubuntu-base-24.04.5-base-arm64.tar.gz" -C "$host"
    touch "$work/build/ubuntu-base.complete"
fi
if [[ ! -f "$work/build/ubuntu-packages.complete" ]]; then
    cp /etc/resolv.conf "$host/etc/resolv.conf"
    printf '#!/bin/sh\nexit 101\n' > "$host/usr/sbin/policy-rc.d"
    chmod 0755 "$host/usr/sbin/policy-rc.d"
    packages=(libgl1-mesa-dri libegl1 libgles2 libglx-mesa0 libgl1 busybox-static
        util-linux e2fsprogs kmod ca-certificates linux-firmware)
    unshare --mount bash "$project/scripts/in-namespace.sh" "$host" apt-get update
    unshare --mount bash "$project/scripts/in-namespace.sh" "$host" \
        apt-get --print-uris --yes --no-install-recommends install "${packages[@]}" > "$work/logs/apt-download-uris.txt"
    python3 "$project/scripts/download-apt.py" "$work/logs/apt-download-uris.txt" "$host/var/cache/apt/archives"
    unshare --mount bash "$project/scripts/in-namespace.sh" "$host" \
        /usr/bin/env DEBIAN_FRONTEND=noninteractive apt-get --no-download --yes --no-install-recommends install "${packages[@]}"
    touch "$work/build/ubuntu-packages.complete"
fi

