#!/usr/bin/env bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
systemctl enable sailfish-live.service NetworkManager.service systemd-networkd.service \
    systemd-resolved.service systemd-timesyncd.service ssh.service
systemctl set-default graphical.target
systemctl mask systemd-networkd-wait-online.service NetworkManager-wait-online.service
if ! id live >/dev/null 2>&1; then
    useradd -m -s /bin/bash -G sudo,audio,video,render,input live
fi
echo 'live:live' | chpasswd
printf 'live ALL=(ALL) NOPASSWD: ALL\n' > /etc/sudoers.d/live
chmod 0440 /etc/sudoers.d/live
for terminal in ttyAMA0 ttyMSM0; do
    mkdir -p "/etc/systemd/system/serial-getty@$terminal.service.d"
    cat > "/etc/systemd/system/serial-getty@$terminal.service.d/live.conf" <<'EOF'
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin live --noclear --keep-baud 115200,57600,38400,9600 - $TERM
EOF
done
mkdir -p /etc/systemd/system/ssh.service.d
cat > /etc/systemd/system/ssh.service.d/live.conf <<'EOF'
[Service]
ExecStartPre=
ExecStartPre=/usr/bin/ssh-keygen -A
ExecStartPre=/usr/sbin/sshd -t
EOF
rm -f /etc/ssh/ssh_host_*key /etc/ssh/ssh_host_*key.pub
chmod 0755 /usr/local/bin/sailfish-session
printf 'sailfish-nabu-live\n' > /etc/hostname
printf '127.0.0.1 localhost\n127.0.1.1 sailfish-nabu-live\n::1 localhost ip6-localhost\n' > /etc/hosts
printf 'Sailfish OS 5.3.0.15 on Ubuntu Base for Xiaomi Pad 5\nConsole and SSH user live, password live\nSailfish user defaultuser, password live\n' > /etc/issue
dpkg-query -W -f='${Package}\t${Version}\t${Architecture}\n' > /etc/ubuntu-live-packages.tsv
rm -f /usr/sbin/policy-rc.d /etc/machine-id /var/lib/dbus/machine-id /var/lib/systemd/random-seed
touch /etc/machine-id
rm -f /etc/resolv.conf
ln -s /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
