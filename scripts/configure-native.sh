#!/usr/bin/env bash
set -euo pipefail
image_version=$1
[[ $image_version =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]
sed -i "s/^VERSION=.*/VERSION=\"$image_version (Tammela)\"/; s/^VERSION_ID=.*/VERSION_ID=$image_version/; s/^PRETTY_NAME=.*/PRETTY_NAME=\"Sailfish OS $image_version (Tammela)\"/; s/^SAILFISH_BUILD=.*/SAILFISH_BUILD=${image_version##*.}/" /etc/sailfish-release
printf 'Sailfish OS %s (Tammela)\nKernel \\r on an \\m\n\n' "$image_version" > /etc/issue
printf 'Sailfish OS %s (Tammela)\nKernel \\r on an \\m\n\n' "$image_version" > /etc/issue.net
if ! getent passwd 100000 >/dev/null; then
    groupadd -g 100000 defaultuser
    useradd -m -u 100000 -g defaultuser -G users,video,audio,input,render,privileged defaultuser
fi
echo 'defaultuser:live' | chpasswd
echo 'root:live' | chpasswd
/usr/lib/startup/create-home 100000
/usr/lib/startup/hw-groups 100000
usermod -a -G video,audio,input,render,privileged,sailfish-system defaultuser
while IFS= read -r -d '' binary; do
    package_group=$(rpm -qf --qf '[%{FILENAMES} %{FILEGROUPNAME}\n]' "$binary" | awk -v filename="$binary" '$1 == filename {print $2}')
    expected_gid=$(getent group "$package_group" | cut -d: -f3)
    if [[ $(stat -c %g "$binary") != "$expected_gid" ]]; then
        binary_mode=$(stat -c %a "$binary")
        chgrp "$package_group" "$binary"
        chmod "$binary_mode" "$binary"
    fi
done < <(find /usr/bin /usr/libexec -type f -perm /2000 -print0)
printf 'LABEL=SFOS_ROOT / ext4 defaults,noatime 0 1\n' > /etc/fstab
printf 'sailfish-nabu\n' > /etc/hostname
printf '127.0.0.1 localhost sailfish-nabu\n::1 localhost\n' > /etc/hosts
rm -f /etc/resolv.conf
ln -s /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
sed -i 's/^PreferredTechnologies=.*/PreferredTechnologies=ethernet,wifi,bluetooth/; s/^DefaultAutoConnectTechnologies=.*/DefaultAutoConnectTechnologies=ethernet,wifi/' /etc/connman/main-native.conf
systemctl unmask sshd.service sshd.socket
systemctl unmask systemd-resolved.service
systemctl disable sshd.socket
systemctl mask sshd.socket
systemctl enable connman.service systemd-resolved.service sshd.service nabu-display-config.service nabu-grow-root.service nabu-configfs.service
systemctl enable bluetooth.service nabu-bluetooth-address.service tqftpserv.service nabu-hexagonrpcd.service nabu-rmtfs.service
systemctl enable nabu-wifi-mac.service
systemctl enable nabu-camera-setup.service
systemctl enable nabu-accelerometer.service
systemctl enable nabu-doubletap.service
systemctl enable nabu-refresh-rate.service
/usr/local/sbin/nabu-install-display-settings
install -m644 /usr/share/nabu-camera/ViewfinderOutput.qml \
    /usr/lib64/qt5/qml/com/jolla/camera/capture/ViewfinderOutput.qml
sed -i 's|^canberra.filename =.*|canberra.filename = nabu-camera-shutter|' \
    /usr/share/ngfd/events.d/camera_shutter.ini
if ! grep -q '^include /etc/sailjail/permissions/NabuCamera.permission$' /etc/sailjail/permissions/Camera.permission; then
    printf '\ninclude /etc/sailjail/permissions/NabuCamera.permission\n' >> /etc/sailjail/permissions/Camera.permission
fi
for camera_app in jolla-camera jolla-camera-lockscreen; do
    camera_desktop="/usr/share/applications/$camera_app.desktop"
    if [[ -f "$camera_desktop" ]]; then
        sed -i "s|^Exec=.*|Exec=/usr/bin/invoker --type=silica-qt5 --single-instance -- /usr/bin/$camera_app|" "$camera_desktop"
    fi
done
systemctl set-default graphical.target
systemctl mask getty@tty7.service
systemctl enable serial-getty@ttyMSM0.service serial-getty@ttyAMA0.service
if ! grep -q '^Include /etc/ssh/sshd_config.d/' /etc/ssh/sshd_config; then
    sed -i '1i Include /etc/ssh/sshd_config.d/*.conf' /etc/ssh/sshd_config
fi
dconf update
mkdir -p /etc/systemd/journald.conf.d
printf '[Journal]\nStorage=persistent\nSystemMaxUse=128M\n' > /etc/systemd/journald.conf.d/90-nabu.conf
rm -f /etc/ssh/ssh_host_* /etc/machine-id /var/lib/dbus/machine-id /var/lib/systemd/random-seed
find /var/log -type f -delete
rm -rf /lib/modules/4.14.180-SailfishOS
touch /etc/machine-id
ldconfig
depmod -a "$(ls /usr/lib/modules | head -n 1)"
rpm -Va --nofiles --noscripts
rpm -qa --qf '%{NAME}.%{ARCH} %{EPOCHNUM}:%{VERSION}-%{RELEASE}\n' | sort > /etc/sailfish-native-packages.txt
