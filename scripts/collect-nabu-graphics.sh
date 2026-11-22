#!/bin/sh
# Run as root on the tablet. Output contains diagnostics only.
echo '=== DRM nodes and drivers ==='
ls -l /dev/dri /sys/class/drm
for node in /sys/class/drm/card[0-9]*; do
    echo "$node"
    readlink -f "$node/device/driver"
done
echo '=== EGLFS configuration ==='
cat /run/nabu-eglfs.json
systemctl status nabu-display-config --no-pager
journalctl -b -u nabu-display-config --no-pager
echo '=== Graphics environments ==='
cat /var/lib/environment/compositor/*.conf /var/lib/environment/nemo/*.conf
echo '=== Graphics and theme messages ==='
journalctl -b --no-pager | grep -Ei 'mesa|adreno|freedreno|EGL|GL_|GBM|shader|texture|ambience|theme|lipstick|jolla-settings' | tail -n 220
echo '=== Active GPU and graphics libraries ==='
for pid in $(pidof lipstick jolla-settings); do
    echo "Process $pid"
    tr '\000' '\n' < "/proc/$pid/environ" | grep -E '^(QT_|QSG_|EGL|GL_|LIBGL|MESA|FD_|WAYLAND|LD_)'
    grep -Ei 'mesa|gallium|EGL|GLES|drm|dri|gbm' "/proc/$pid/maps" | sort -u
done
echo '=== Kernel graphics messages ==='
dmesg | grep -Ei 'adreno|msm|drm|gpu|firmware' | tail -n 100
echo '=== User theme settings ==='
runuser -u defaultuser -- env XDG_RUNTIME_DIR=/run/user/100000 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/100000/dbus/user_bus_socket dconf dump /desktop/jolla/theme/
runuser -u defaultuser -- env XDG_RUNTIME_DIR=/run/user/100000 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/100000/dbus/user_bus_socket dconf dump /desktop/sailfish/silica/
