#!/usr/bin/env bash
set -euo pipefail
project=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
work=${SFOS_WORK:-/home/bird/data/tmp/sfos-aarch64}
mkdir -p "$work/logs" "$work/build"
export TMPDIR="$work/build"
export TMP="$TMPDIR"
export TEMP="$TMPDIR"
exec bash "$project/scripts/test-installed-qemu.sh"
