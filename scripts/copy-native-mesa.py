#!/usr/bin/env python3
"""Copy the Ubuntu Mesa dependency closure into Sailfish's private library path."""
import collections
import json
import pathlib
import re
import shutil
import subprocess
import sys

host = pathlib.Path(sys.argv[1])
guest = pathlib.Path(sys.argv[2])
destination = guest / "usr/lib/sailfish-native"
destination.mkdir(parents=True, exist_ok=True)
library_directory = host / "usr/lib/aarch64-linux-gnu"
excluded = re.compile(r"^(ld-linux|lib(c|m|pthread|dl|rt|resolv|util)\.so|libwayland-)")
initial = ["libEGL.so.1", "libEGL_mesa.so.0", "libGLESv2.so.2", "libGL.so.1", "libgbm.so.1", "libGLX_mesa.so.0"]
drivers = library_directory / "dri"
driver_files = list(drivers.glob("*.so")) + list((library_directory / "gbm").glob("*.so"))
queue = collections.deque([library_directory / name for name in initial] + driver_files)
copied = set()
while queue:
    source = queue.popleft()
    name = source.name
    if name in copied or excluded.match(name):
        continue
    if not source.exists():
        raise FileNotFoundError(source)
    copied.add(name)
    directory = destination / source.parent.name if source.parent.name in ("dri", "gbm") else destination
    directory.mkdir(exist_ok=True)
    shutil.copyfile(source, directory / name)
    subprocess.run(["patchelf", "--set-rpath", "/usr/lib/sailfish-native", str(directory / name)], check=True)
    dynamic = subprocess.check_output(["aarch64-linux-gnu-readelf", "-d", str(source)], text=True)
    dependencies = re.findall(r"Shared library: \[(.*?)\]", dynamic)
    queue.extend(library_directory / dependency for dependency in dependencies)

glvnd = guest / "usr/share/glvnd/egl_vendor.d"
glvnd.mkdir(parents=True, exist_ok=True)
shutil.copyfile(host / "usr/share/glvnd/egl_vendor.d/50_mesa.json", glvnd / "50_mesa.json")
for name in ["libEGL.so.1", "libGLESv2.so.2", "libGL.so.1", "libgbm.so.1"]:
    link = guest / "usr/lib64" / name
    link.unlink(missing_ok=True)
    link.symlink_to("/usr/lib/sailfish-native/" + name)
(destination / "manifest.json").write_text(json.dumps(sorted(copied), indent=2) + "\n")
default_driver_directory = guest / "usr/lib/aarch64-linux-gnu/dri"
default_driver_directory.parent.mkdir(parents=True, exist_ok=True)
if not default_driver_directory.exists() and not default_driver_directory.is_symlink():
    default_driver_directory.symlink_to("/usr/lib/sailfish-native/dri")
print("Copied", len(copied), "native graphics libraries")
default_gbm_directory = guest / "usr/lib/aarch64-linux-gnu/gbm"
if not default_gbm_directory.exists() and not default_gbm_directory.is_symlink():
    default_gbm_directory.symlink_to("/usr/lib/sailfish-native/gbm")
