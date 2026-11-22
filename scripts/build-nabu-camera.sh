#!/usr/bin/env bash
set -euo pipefail
project=$1
work=$2
cache="$work/cache/nabu-camera-headers"
output="$work/build/native-camera"
python3 "$project/scripts/prepare-nabu-camera-headers.py" \
    "$project/config/nabu-camera-build-headers.json" "$cache"
mkdir -p "$output"
camera_compiler=aarch64-linux-gnu-gcc
if [[ -v CROSS_COMPILE ]]; then
    camera_compiler="$CROSS_COMPILE"gcc
fi
"$camera_compiler" \
    -D_GNU_SOURCE -DPACKAGE='"nabu-native"' -shared -fPIC -O2 -Wall -Wextra \
    -I"$cache/headers/usr/include/gstreamer-1.0" \
    -I"$cache/headers/usr/include/glib-2.0" \
    -I"$cache/headers/usr/lib/aarch64-linux-gnu/glib-2.0/include" \
    -o "$output/libgstnabucamera.so" "$project/source/nabu-camera-preview/gstnabucamerasrc.c" \
    -L"$work/build/native-root/usr/lib64" \
    -l:libgstbase-1.0.so.0 -l:libgstreamer-1.0.so.0 \
    -l:libgobject-2.0.so.0 -l:libglib-2.0.so.0 -lm

# Qt's native enumeration omits CAMSS multi-plane devices. Supply the two
# logical devices to Qt 5.6 using its existing camera descriptor ABI.
camera_cxx="$cache/headers/usr/aarch64-linux-gnu/include/c++/12"
camera_qt="$cache/headers/usr/include/aarch64-linux-gnu/qt5"
"$camera_compiler" -x c++ -std=c++11 -shared -fPIC -O2 -Wall -Wextra \
    -DQT_NO_VERSION_TAGGING -DQT_CORE_LIB -DQT_MULTIMEDIA_LIB \
    -B"$cache/headers/usr/lib/gcc-cross/aarch64-linux-gnu/12/" \
    -nostdinc++ -isystem "$("$camera_compiler" -print-file-name=include)" \
    -isystem "$camera_cxx" -isystem "$camera_cxx/aarch64-linux-gnu" \
    -I"$camera_qt" -I"$camera_qt/QtCore" -I"$camera_qt/QtMultimedia" \
    -o "$output/libnabu-qtcamera.so" "$project/source/nabu-camera-preview/qtcamera.cpp" \
    -L"$work/build/native-root/usr/lib64" -l:libQt5Core.so.5 -l:libstdc++.so.6
