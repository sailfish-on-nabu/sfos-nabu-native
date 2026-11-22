#!/usr/bin/env bash
set -euo pipefail
host_audio_gid=$1
host_render_gid=$2
if ! getent passwd 100000 >/dev/null; then
    groupadd -g 100000 defaultuser
    useradd -m -u 100000 -g defaultuser -G users,video,audio,input,render,privileged defaultuser
fi
echo 'defaultuser:live' | chpasswd
/usr/lib/startup/create-home 100000
/usr/lib/startup/hw-groups 100000
for host_gid in "$host_audio_gid" "$host_render_gid"; do
    if ! getent group "$host_gid" >/dev/null; then
        groupadd -g "$host_gid" "host-device-$host_gid"
    fi
    usermod -a -G "$host_gid" defaultuser
done
chmod 0755 /usr/local/bin/sailfish-lipstick
# Restore stale numeric SGID groups using the installed RPM ownership names.
while IFS= read -r -d '' binary; do
    package_group=$(rpm -qf --qf '[%{FILENAMES} %{FILEGROUPNAME}\n]' "$binary" |
        awk -v filename="$binary" '$1 == filename {print $2}')
    expected_gid=$(getent group "$package_group" | cut -d: -f3)
    if [[ $(stat -c %g "$binary") != "$expected_gid" ]]; then
        binary_mode=$(stat -c %a "$binary")
        chgrp "$package_group" "$binary"
        chmod "$binary_mode" "$binary"
    fi
done < <(find /usr/bin /usr/libexec -type f -perm /2000 -print0)
rm -f /etc/resolv.conf
ln -s /run/host-resolve/resolv.conf /etc/resolv.conf
systemctl set-default graphical.target
systemctl enable connman.service
systemctl unmask droid-hal-init.service droid-late-start.service droid-bootctl.service \
    droid-hcismd-up.service droid-reclaim-memory.service \
    dev-binderfs.mount config.mount linkerconfig.mount mnt-vendor-persist.mount \
    dmsetup.service metadata.mount odm_root.mount product.mount \
    system_ext.mount system.mount system_root.mount vendor-bt_firmware.mount \
    vendor-dsp.mount vendor-firmware_mnt.mount vendor.mount wait-for-wifi.service \
    wlan-module-load.service bluebinder.service wait_for_keymaster.service \
    audiosystem-passthrough-dummy-af.service
systemctl mask quota_nld.service systemd-resolved.service sshd.socket sshd.service
printf '' > /etc/fstab
rm -f /etc/pulse/default_sailfish.pa.d/droid.pa
rm -f /etc/pulse/default_sailfish.pa.d/90-mainline.pa /etc/pulse/bluez5_discover_custom.pa
rpm -qa --qf '%{NAME}.%{ARCH} %{EPOCHNUM}:%{VERSION}-%{RELEASE}\n' | sort > /etc/sailfish-live-packages.txt
rm -f /etc/machine-id /var/lib/dbus/machine-id
touch /etc/machine-id
