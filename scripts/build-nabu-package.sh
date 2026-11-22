#!/usr/bin/env bash
set -euo pipefail
project=$1
work=$2
image_version=$(cat "$project/config/image-version")
guest="$work/build/native-root"
payload="$work/build/nabu-package-payload"
top="$work/build/nabu-rpm"
mkdir -p "$payload" "$top"/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS,tmp}
rsync -a --delete "$project/overlay/native/" "$payload/"
mkdir -p "$work/build/native-audio"
aarch64-linux-gnu-gcc -shared -fPIC -O2 -Wall -Wextra -Werror \
    "$project/source/nabu-audio/highpass.c" -lm \
    -o "$work/build/native-audio/nabu_highpass.so"
install -Dm755 "$work/build/native-audio/nabu_highpass.so" \
    "$payload/usr/lib64/ladspa/nabu_highpass.so"
install -Dm644 "$project/source/nabu-audio/LICENSE.ladspa" \
    "$payload/usr/share/licenses/sfos-nabu-native/ladspa-header.txt"
printf 'IMAGE_VERSION=%s\nBASE_RELEASE=5.3.0.15\n' "$image_version" > "$payload/etc/sailfish-native-image-release"
bash "$project/scripts/build-qcom-services.sh" "$project" "$work"
rsync -a "$work/build/qcom-services/usr/" "$payload/usr/"
bash "$project/scripts/build-nabu-camera.sh" "$project" "$work"
install -Dm755 "$work/build/native-camera/libgstnabucamera.so" \
    "$payload/usr/lib64/gstreamer-1.0/libgstnabucamera.so"
install -Dm755 "$work/build/native-camera/libnabu-qtcamera.so" \
    "$payload/usr/lib/sailfish-native/libnabu-qtcamera.so"
install -Dm644 "$project/source/nabu-camera-preview/nabu_camera.py" \
    "$payload/usr/libexec/nabu-camera/nabu_camera.py"
install -Dm755 "$project/source/nabu-camera-preview/setup.py" \
    "$payload/usr/libexec/nabu-camera/setup.py"
install -Dm644 "$project/source/nabu-sensors/ssc-accelerometer.py" \
    "$payload/usr/libexec/nabu-sensors/ssc-accelerometer.py"
python3 "$project/scripts/prepare-nabu-camera-sound.py" \
    "$payload/usr/share/sounds/jolla-ambient/stereo/nabu-camera-shutter.wav"
mkdir -p "$payload/usr/lib/modules" "$payload/usr/lib/firmware" "$payload/boot" "$payload/usr/share/alsa/ucm2"
rsync -aH "$work/build/kernel-modules/lib/modules/" "$payload/usr/lib/modules/"
mkdir -p "$payload/lib/modules"
version=$(cat "$project/dist/kernel/kernel-release.txt")
ln -sfn "/usr/lib/modules/$version" "$payload/lib/modules/$version"
ln -sfn /usr/lib/firmware "$payload/lib/firmware"
find "$payload/usr/lib/modules" -name build -type l -delete
tar -xpf "$work/downloads/nabu-firmware.pkg.tar.xz" -C "$payload" usr/lib/firmware usr/share/qcom
# The device firmware archive depends on the separate Atheros firmware package.
# Materialize the WCN3990/QCA blobs so symlinks and compression are self-contained.
python3 - "$work/build/ubuntu-root/usr/lib/firmware" "$payload/usr/lib/firmware" <<'PY'
from pathlib import Path
import subprocess
import sys
source, destination = map(Path, sys.argv[1:])
for subdirectory in ('ath10k/WCN3990', 'qca'):
    base = source / subdirectory
    if not base.is_dir():
        raise FileNotFoundError(base)
    for path in base.rglob('*'):
        if not path.is_file():
            continue
        relative = path.relative_to(source)
        target = destination / relative
        if path.suffix == '.zst':
            target = target.with_suffix('')
        target.parent.mkdir(parents=True, exist_ok=True)
        if path.suffix == '.zst':
            with target.open('wb') as output:
                subprocess.run(['zstd', '-dc', str(path.resolve())], stdout=output, check=True)
        else:
            target.write_bytes(path.read_bytes())
PY
cp "$project/dist/kernel/Image.gz" "$project/dist/kernel/sm8150-xiaomi-nabu.dtb" "$payload/boot/"
cp "$project/dist/kernel/config-$version" "$project/dist/kernel/kernel-release.txt" "$payload/boot/"
mkdir -p "$payload/usr/share/alsa/ucm2/Xiaomi/nabu" "$payload/usr/share/alsa/ucm2/conf.d/sm8150"
rsync -a "$project/inputs/alsa/ucm2/" "$payload/usr/share/alsa/ucm2/"
install -Dm644 "$project/inputs/alsa/LICENSE.alsa-ucm-conf" \
    "$payload/usr/share/licenses/sfos-nabu-native/alsa-ucm-conf.txt"
cp "$project/inputs/alsa/HiFi.conf" "$project/inputs/alsa/Speaker.conf" "$payload/usr/share/alsa/ucm2/Xiaomi/nabu/"
cp "$project/inputs/alsa/sm8150.conf" "$payload/usr/share/alsa/ucm2/conf.d/sm8150/"
chmod 0755 "$payload/usr/local/bin/"* "$payload/usr/local/sbin/"*
python3 - "$payload" "$top/files.list" <<'PY'
import sys
from pathlib import Path
root = Path(sys.argv[1])
files = []
for path in sorted(root.rglob('*')):
    if path.is_file() or path.is_symlink():
        name = '/' + str(path.relative_to(root))
        prefix = '%config(noreplace) ' if name.startswith('/etc/') else ''
        files.append(prefix + name)
Path(sys.argv[2]).write_text(chr(10).join(files) + chr(10))
PY
rpmbuild -bb --target aarch64-linux \
    --define "image_version $image_version" \
    --define "_topdir $top" --define "_tmppath $top/tmp" \
    --define "nabu_payload $payload" --define "nabu_files $top/files.list" \
    "$project/config/nabu-native.spec"
cp "$top/RPMS/aarch64/sfos-nabu-native-$image_version-1.aarch64.rpm" "$project/dist/"
