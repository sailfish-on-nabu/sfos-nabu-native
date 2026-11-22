Name: sfos-mainline-runtime
Version: %{image_version}
Release: 1
Summary: Native Mesa graphics and mainline system configuration for Sailfish
License: Mixed open-source licenses
Provides: ohm-configs = %{version}
Provides: bluez5-configs
Provides: usb-moded-configs
Provides: pulseaudio-settings

%global debug_package %{nil}
%global __os_install_post %{nil}

%description
Native Mesa EGL, GLES and DRM libraries with legacy Wayland buffer sharing,
Ubuntu Base GLVND frontends and dependencies, with the generic
policy, network, Bluetooth, sensor and USB configuration used by this mainline image.

%install
mkdir -p %{buildroot}
cp -a %{runtime_payload}/. %{buildroot}/

%files
%defattr(-,root,root,-)
/usr/lib/sailfish-native
/usr/lib64/libEGL.so.1
/usr/lib64/libGLESv2.so.2
/usr/lib64/libGL.so.1
/usr/lib64/libgbm.so.1
/usr/lib/aarch64-linux-gnu/dri
/usr/lib/aarch64-linux-gnu/gbm
/usr/share/glvnd/egl_vendor.d/50_mesa.json
%config(noreplace) /etc/ohm/dbus_method_conf.ini
%config(noreplace) /etc/ohm/dbus_signal_conf.ini
%config(noreplace) /etc/ohm/modules.ini
%config(noreplace) /etc/ohm/ohmd.ini
%config(noreplace) /etc/dbus-1/system.d/ohm-policy.conf
%config(noreplace) /etc/ohm/plugins.d/dbus_method.ini
%config(noreplace) /etc/ohm/plugins.d/dbus_signal.ini
%config(noreplace) /etc/bluez5/bluetooth/main.conf
%config(noreplace) /etc/usb-moded/20-mainline.ini
%config(noreplace) /etc/sensorfw/primaryuse.conf
%config(noreplace) /etc/sysconfig/pulseaudio
%config(noreplace) /etc/connman/main-native.conf
%config(noreplace) /etc/ld.so.conf.d/00-000-nabu-native-graphics.conf
