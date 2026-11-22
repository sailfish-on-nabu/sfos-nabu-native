#!/usr/bin/env bash
set -euo pipefail
exclusion_file=$1
native_rpm=$2
mapfile -t installed_packages < <(rpm -qa --qf '%{NAME}\n')
packages_to_remove=()
while IFS= read -r package; do
    if printf '%s\n' "${installed_packages[@]}" | /bin/grep -Fx "$package" >/dev/null; then
        packages_to_remove+=("$package")
    fi
done < "$exclusion_file"

# The native libraries supply the EGL/GLES interfaces required by Qt.
rpm -Uvh --replacefiles --replacepkgs "$native_rpm"
if (( ${#packages_to_remove[@]} )); then
    rpm -e --test "${packages_to_remove[@]}"
    rpm -e "${packages_to_remove[@]}"
fi
rpm -Va --nofiles --noscripts
ldconfig
