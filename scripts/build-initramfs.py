#!/usr/bin/env python3
import gzip
import os
import pathlib
import re
import shutil
import stat
import subprocess
import sys

project = pathlib.Path(sys.argv[1])
work = pathlib.Path(sys.argv[2])
host = work / "build/ubuntu-root"
root = work / "build/initramfs"
version = (project / "dist/kernel/kernel-release.txt").read_text().strip()
if root.exists():
    shutil.rmtree(root)
for directory in ["bin", "sbin", "dev", "proc", "sys", "run", "tmp", "lib/modules/" + version]:
    (root / directory).mkdir(parents=True, exist_ok=True)
shutil.copyfile(host / "bin/busybox", root / "bin/busybox")
(root / "bin/busybox").chmod(0o755)
applets = ["sh", "mount", "mkdir", "modprobe", "echo", "seq", "sed", "head", "sleep", "switch_root", "cat", "ls", "dmesg", "mknod", "uname", "reboot", "poweroff"]
available = subprocess.check_output(["qemu-aarch64-static", str(host / "bin/busybox"), "--list"], text=True).splitlines()
missing = set(applets) - set(available)
if missing:
    raise ValueError("Missing initramfs applets: " + ", ".join(sorted(missing)))
for name in applets:
    (root / "bin" / name).symlink_to("busybox")
# Ubuntu's static BusyBox relies on util-linux for block-device identification.
shutil.copyfile(host / "usr/sbin/blkid", root / "bin/blkid")
(root / "bin/blkid").chmod(0o755)
(root / "lib/aarch64-linux-gnu").mkdir(parents=True, exist_ok=True)
for name in ["libblkid.so.1", "libc.so.6"]:
    shutil.copyfile(host / "usr/lib/aarch64-linux-gnu" / name, root / "lib/aarch64-linux-gnu" / name)
shutil.copyfile(host / "usr/lib/aarch64-linux-gnu/ld-linux-aarch64.so.1", root / "lib/ld-linux-aarch64.so.1")
(root / "lib/ld-linux-aarch64.so.1").chmod(0o755)
queue = [host / "usr/sbin/e2fsck"]
copied = set()
while queue:
    source = queue.pop()
    if source.name in copied:
        continue
    copied.add(source.name)
    directory = root / ("bin" if source.name == "e2fsck" else "lib/aarch64-linux-gnu")
    shutil.copyfile(source, directory / source.name)
    (directory / source.name).chmod(0o755)
    dynamic = subprocess.check_output(["aarch64-linux-gnu-readelf", "-d", str(source)], text=True)
    for line in dynamic.splitlines():
        if "Shared library:" in line:
            dependency = line.split("[", 1)[1].split("]", 1)[0]
            queue.append(host / "usr/lib/aarch64-linux-gnu" / dependency)
shutil.copyfile(project / "config/init", root / "init")
image_version = (project / "config/image-version").read_text().strip()
(root / "init").write_text((root / "init").read_text().replace("@IMAGE_VERSION@", image_version))
(root / "init").chmod(0o755)
module_root = work / "build/kernel-modules"
module_directory = module_root / "lib/modules" / version
for name in ["modules.dep", "modules.alias", "modules.builtin", "modules.builtin.modinfo", "modules.softdep"]:
    if (module_directory / name).exists():
        shutil.copyfile(module_directory / name, root / "lib/modules" / version / name)
early_modules = ["panel-novatek-nt36523", "nt36523_ts"]
for module in early_modules:
    dependencies = subprocess.check_output(["modprobe", "--show-depends", "--dirname", str(module_root), "--set-version", version, module], text=True)
    for line in dependencies.splitlines():
        if line.startswith("insmod "):
            source = pathlib.Path(line.split()[1])
            relative = source.resolve().relative_to(module_directory.resolve())
            destination = root / "lib/modules" / version / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, destination)
for name in ["qcom/a630_sqe.fw", "qcom/a640_gmu.bin", "qcom/sm8150/xiaomi/nabu/a640_zap.mbn", "novatek/novatek_nt36523_fw.bin"]:
    destination = root / "lib/firmware" / name
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(work / "build/native-root/usr/lib/firmware" / name, destination)

def cpio_entry(output, name, mode, data, inode, rdevmajor=0, rdevminor=0):
    encoded = name.encode() + b"\0"
    fields = [inode, mode, 0, 0, 1, 0, len(data), 0, 0, rdevmajor, rdevminor, len(encoded), 0]
    header = b"070701" + b"".join(f"{value:08x}".encode() for value in fields)
    output.write(header + encoded)
    output.write(b"\0" * (-(len(header) + len(encoded)) % 4))
    output.write(data)
    output.write(b"\0" * (-len(data) % 4))

target = project / "dist/initramfs.cpio.gz"
with target.open("wb") as compressed, gzip.GzipFile(fileobj=compressed, mode="wb", mtime=0, compresslevel=9) as output:
    for inode, path in enumerate(sorted(root.rglob("*")), 1):
        mode = path.lstat().st_mode
        data = os.readlink(path).encode() if path.is_symlink() else path.read_bytes() if path.is_file() else b""
        cpio_entry(output, str(path.relative_to(root)), mode, data, inode)
    cpio_entry(output, "dev/console", stat.S_IFCHR | 0o600, b"", 100000, 5, 1)
    cpio_entry(output, "dev/null", stat.S_IFCHR | 0o666, b"", 100001, 1, 3)
    cpio_entry(output, "TRAILER!!!", 0, b"", 100002)
print(target, target.stat().st_size)
