#!/usr/bin/env bash
set -euo pipefail
project=$1
work=$2
reference="$project/source/reference"
output="$work/build/qcom-services"
mkdir -p "$output/usr/bin" "$output/usr/share/licenses/sfos-nabu-native"
for repository in qrtr tqftpserv hexagonrpc rmtfs; do
    if [[ ! -d "$reference/$repository/.git" ]]; then
        git clone --depth=1 --single-branch "https://github.com/linux-msm/$repository.git" "$reference/$repository"
    fi
done
python3 - "$reference" "$project/inputs/qcom-service-sources.json" <<'PY'
import json
import hashlib
import subprocess
import sys
from pathlib import Path
root = Path(sys.argv[1])
revisions = {}
for name in ('qrtr', 'tqftpserv', 'hexagonrpc', 'rmtfs'):
    revisions[name] = subprocess.check_output(['git', '-C', str(root / name), 'rev-parse', 'HEAD'], text=True).strip()
Path(sys.argv[2]).write_text(json.dumps(revisions, indent=2) + chr(10))
patch = root.parent.parent / 'config/patches/hexagonrpc-pr27-write-support.patch'
if patch.exists():
    revisions['hexagonrpc_write_support_patch_sha256'] = hashlib.sha256(patch.read_bytes()).hexdigest()
    Path(sys.argv[2]).write_text(json.dumps(revisions, indent=2) + chr(10))
PY
cc=aarch64-linux-gnu-gcc
"$cc" -O2 -Wall -I"$reference/qrtr/include" -I"$reference/qrtr/lib" \
    "$reference/tqftpserv/tqftpserv.c" "$reference/tqftpserv/translate.c" \
    "$reference/qrtr/lib/qrtr.c" "$reference/qrtr/lib/qmi.c" "$reference/qrtr/lib/logging.c" \
    -o "$output/usr/bin/tqftpserv"
"$cc" -O2 -Wall -I"$reference/qrtr/include" -I"$reference/qrtr/lib" \
    "$reference/qrtr/src/lookup.c" "$reference/qrtr/lib/qrtr.c" \
    "$reference/qrtr/lib/qmi.c" "$reference/qrtr/lib/logging.c" \
    -o "$output/usr/bin/qrtr-lookup"
hexagon="$reference/hexagonrpc"
patch="$project/config/patches/hexagonrpc-pr27-write-support.patch"
if git -C "$hexagon" apply --check "$patch" 2>/dev/null; then
    git -C "$hexagon" apply "$patch"
else
    git -C "$hexagon" apply --reverse --check "$patch"
fi
mkdir -p "$output/include/misc"
cp "$project/source/linux/include/uapi/misc/fastrpc.h" "$output/include/misc/"
"$cc" -O2 -Wall -D_GNU_SOURCE -Wno-unused-parameter -I"$output/include" -I"$hexagon/include" \
    -I"$hexagon/hexagonrpcd" -I"$hexagon/libhexagonrpc" \
    "$hexagon/libhexagonrpc/"*.c "$hexagon/libhexagonrpc/interface/remotectl.c" \
    "$hexagon/hexagonrpcd/"*.c "$hexagon/hexagonrpcd/interface/"*.c \
    -o "$output/usr/bin/hexagonrpcd"
mkdir -p "$output/include"
cp /usr/include/libudev.h "$output/include/"
"$cc" -O2 -Wall -Wl,--allow-shlib-undefined -I"$output/include" \
    -I"$reference/qrtr/include" -I"$reference/qrtr/lib" \
    "$reference/rmtfs/"{qmi_rmtfs,rmtfs,rproc,sharedmem,storage,util}.c \
    "$reference/qrtr/lib/"{qrtr,qmi,logging}.c \
    "$work/build/native-root/usr/lib64/libudev.so.1" -pthread \
    -o "$output/usr/bin/rmtfs"
for program in "$output/usr/bin/"*; do
    aarch64-linux-gnu-strip "$program"
done
cp "$reference/tqftpserv/LICENSE" "$output/usr/share/licenses/sfos-nabu-native/tqftpserv.txt"
cp "$reference/qrtr/LICENSE" "$output/usr/share/licenses/sfos-nabu-native/qrtr.txt"
cp "$reference/hexagonrpc/COPYING" "$output/usr/share/licenses/sfos-nabu-native/hexagonrpc.txt"
cp "$reference/rmtfs/LICENSE" "$output/usr/share/licenses/sfos-nabu-native/rmtfs.txt"
