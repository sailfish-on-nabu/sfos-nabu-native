#!/usr/bin/env bash
set -euo pipefail
project=$1
work=$2
image_version=$(cat "$project/config/image-version")
guest="$work/build/native-root"
original=/home/bird/data/hadk_18.1/SailfishOScommunity-release-5.3.0.15-nabu-alpha1
bash "$project/scripts/prepare-build-tools.sh" "$project" "$work"
mkdir -p "$guest"
if [[ ! -f "$work/build/native-root.complete" ]]; then
    tar --numeric-owner --exclude='./dev/*' -xpf "$original/sfe-nabu-5.3.0.15-alpha1.tar.bz2" -C "$guest"
    touch "$work/build/native-root.complete"
fi
python3 "$project/scripts/build-native-mesa.py" "$project" "$work"
python3 "$project/scripts/copy-native-mesa.py" "$work/build/ubuntu-root" "$guest" "$work/build/native-mesa/payload"
SFOS_GUEST_ROOT="$guest" bash "$project/scripts/build-native-runtime.sh" "$project" "$work"
bash "$project/scripts/build-nabu-package.sh" "$project" "$work"
cp "$project/dist/sfos-mainline-runtime-$image_version-1.aarch64.rpm" "$guest/tmp/"
cp "$project/scripts/remove-android-packages.sh" "$guest/tmp/"
cp "$project/config/excluded-packages.txt" "$guest/tmp/"
unshare --mount bash "$project/scripts/in-namespace.sh" "$guest" /bin/bash \
    /tmp/remove-android-packages.sh /tmp/excluded-packages.txt "/tmp/sfos-mainline-runtime-$image_version-1.aarch64.rpm"
cp "$work/downloads/qt5-plugin-platform-eglfs-5.6.3+git60-1.19.10.jolla.aarch64.rpm" "$guest/tmp/"
cp "$project/dist/sfos-nabu-native-$image_version-1.aarch64.rpm" "$guest/tmp/"
# Native QML adaptations also replace files supplied by the stock settings package.
unshare --mount bash "$project/scripts/in-namespace.sh" "$guest" /usr/bin/rpm -Uvh --replacepkgs --replacefiles \
    /tmp/qt5-plugin-platform-eglfs-5.6.3+git60-1.19.10.jolla.aarch64.rpm \
    "/tmp/sfos-nabu-native-$image_version-1.aarch64.rpm"
cp "$project/scripts/configure-native.sh" "$guest/tmp/"
unshare --mount bash "$project/scripts/in-namespace.sh" "$guest" /bin/bash /tmp/configure-native.sh "$image_version"
rm -f "$guest/tmp/"*.rpm "$guest/tmp/remove-android-packages.sh" "$guest/tmp/excluded-packages.txt" "$guest/tmp/configure-native.sh"
python3 "$project/scripts/audit-packages.py" "$project/inputs/Jolla-5.3.0.15-nabu-aarch64.packages" \
    "$guest/etc/sailfish-native-packages.txt" "$project/dist/package-audit.json" \
    --exclude "$project/config/excluded-packages.txt" --native-package sfos-mainline-runtime.aarch64 \
    --native-package sfos-nabu-native.aarch64 --native-package qt5-plugin-platform-eglfs.aarch64
cp "$guest/etc/sailfish-native-packages.txt" "$project/dist/sailfish-packages.txt"
