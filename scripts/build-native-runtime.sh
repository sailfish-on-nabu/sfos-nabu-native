#!/usr/bin/env bash
set -euo pipefail
project=$1
work=$2
image_version=$(cat "$project/config/image-version")
guest="${SFOS_GUEST_ROOT:-$work/build/sailfish-root}"
payload="$work/build/native-runtime-payload"
rpm_directory="$work/build/native-rpm"
mkdir -p "$payload/usr/lib" "$payload/usr/lib64" "$payload/usr/lib/aarch64-linux-gnu" \
    "$payload/usr/share/glvnd/egl_vendor.d" "$rpm_directory"/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS,tmp}
rsync -a "$guest/usr/lib/sailfish-native/" "$payload/usr/lib/sailfish-native/"
for library in libEGL.so.1 libGLESv2.so.2 libGL.so.1 libgbm.so.1; do
    ln -sfn "/usr/lib/sailfish-native/$library" "$payload/usr/lib64/$library"
done
ln -sfn /usr/lib/sailfish-native/dri "$payload/usr/lib/aarch64-linux-gnu/dri"
ln -sfn /usr/lib/sailfish-native/gbm "$payload/usr/lib/aarch64-linux-gnu/gbm"
cp "$guest/usr/share/glvnd/egl_vendor.d/50_mesa.json" "$payload/usr/share/glvnd/egl_vendor.d/"
rsync -a "$project/overlay/runtime/" "$payload/"
rpmbuild -bb --target aarch64-linux \
    --define "image_version $image_version" \
    --define "_topdir $rpm_directory" --define "_tmppath $rpm_directory/tmp" \
    --define "runtime_payload $payload" "$project/config/mainline-runtime.spec"
cp "$rpm_directory/RPMS/aarch64/sfos-mainline-runtime-$image_version-1.aarch64.rpm" "$project/dist/"
