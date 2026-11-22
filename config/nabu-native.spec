Name: sfos-nabu-native
Version: %{image_version}
Release: 1
Summary: Xiaomi Pad 5 native Sailfish adaptation
License: GPL-2.0-only AND BSD-3-Clause AND MIT AND LicenseRef-Firmware
Requires: sfos-mainline-runtime
Requires: qt5-plugin-platform-eglfs
Requires: e2fsprogs
%global debug_package %{nil}
%global __os_install_post %{nil}
# Firmware and kernel modules are not userspace ELF dependencies.
%global __requires_exclude_from ^/usr/lib/(firmware|modules)/.*$
%global __provides_exclude_from ^/usr/lib/(firmware|modules)/.*$
%description
Native EGLFS/KMS configuration, SM8150 kernel modules, nabu firmware,
ALSA UCM and persistent root filesystem integration for Xiaomi Pad 5.
%install
mkdir -p %{buildroot}
cp -a %{nabu_payload}/. %{buildroot}/
%files -f %{nabu_files}
%defattr(-,root,root,-)
