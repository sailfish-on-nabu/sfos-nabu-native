#!/usr/bin/env python3
"""Build the Mesa Wayland buffer interface required by the Qt 5.6 compositor."""
import hashlib
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import sys
import tarfile
import urllib.request

project, work = map(lambda p: Path(p).resolve(), sys.argv[1:])
manifest = project / 'config/native-mesa-build.json'
config = json.loads(manifest.read_text())
base = work / 'build/native-mesa'
sdk_cache = work / 'cache/native-mesa-sdk'
sdk = sdk_cache / 'headers'
payload = base / 'payload'
marker = base / 'complete.json'
base.mkdir(parents=True, exist_ok=True)


def sha256(path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(4 * 1024 * 1024), b''):
            digest.update(block)
    return digest.hexdigest()


cc = shutil.which('aarch64-linux-gnu-gcc')
if not cc:
    raise SystemExit('The aarch64-linux-gnu C compiler is required.')
fingerprint = hashlib.sha256(manifest.read_bytes() + Path(__file__).read_bytes()
                             + subprocess.check_output([cc, '--version'])).hexdigest()
if marker.exists():
    previous = json.loads(marker.read_text())
    if previous.get('fingerprint') == fingerprint and all(
            (payload / name).is_file() and sha256(payload / name) == digest
            for name, digest in previous['files'].items()) and all(
            (payload / name).is_symlink() and str((payload / name).readlink()) == target
            for name, target in previous.get('links', {}).items()):
        print('Verified cached native Mesa', config['version'])
        sys.exit(0)

subprocess.run(['python3', str(project / 'scripts/prepare-nabu-camera-headers.py'),
                str(manifest), str(sdk_cache)], check=True)
venv = base / 'venv'
if not (venv / 'bin/meson').exists():
    subprocess.run(['python3', '-m', 'venv', str(venv)], check=True)
requirements = json.dumps(config['python_requirements'])
requirements_marker = venv / 'requirements.json'
if not requirements_marker.exists() or requirements_marker.read_text() != requirements:
    subprocess.run([str(venv / 'bin/pip'), 'install', *config['python_requirements']], check=True)
    requirements_marker.write_text(requirements)
env = os.environ.copy()
env['PATH'] = str(venv / 'bin') + ':' + env['PATH']
archive = work / 'downloads' / config['source']['name']
archive.parent.mkdir(parents=True, exist_ok=True)
if not archive.exists() or sha256(archive) != config['source']['sha256']:
    temporary = archive.with_suffix('.partial')
    with urllib.request.urlopen(config['source']['url'], timeout=120) as source, temporary.open('wb') as target:
        shutil.copyfileobj(source, target)
    if sha256(temporary) != config['source']['sha256']:
        raise SystemExit('Mesa source archive checksum mismatch.')
    temporary.replace(archive)
source_parent = work / 'source/native-mesa'
source = source_parent / ('mesa-' + config['version'])
if not source.exists():
    source_parent.mkdir(parents=True, exist_ok=True)
    with tarfile.open(archive) as packed:
        packed.extractall(source_parent)

native_pc = base / 'native-pkgconfig'
native_pc.mkdir(exist_ok=True)
(native_pc / 'wayland-scanner.pc').write_text(
    f'wayland_scanner={sdk}/usr/bin/wayland-scanner\n\n'
    'Name: Wayland Scanner\nDescription: Native protocol scanner\nVersion: 1.20.0\n')
compiler_dir = sdk / 'usr/lib/gcc-cross/aarch64-linux-gnu/12'
cxx = base / 'cxx'
cxx_arguments = [str(sdk / 'usr/bin/aarch64-linux-gnu-g++-12'),
                 '-B' + str(compiler_dir) + '/', '-B/usr/lib/gcc-cross/aarch64-linux-gnu/11/',
                 '-B/usr/aarch64-linux-gnu/bin/', '-B/usr/aarch64-linux-gnu/lib/',
                 '-L/usr/aarch64-linux-gnu/lib', '-L' + str(sdk / 'usr/lib/aarch64-linux-gnu'),
                 '-isystem', str(compiler_dir / 'include'), '-isystem', '/usr/aarch64-linux-gnu/include',
                 '-nostdinc++', '-isystem', str(sdk / 'usr/aarch64-linux-gnu/include/c++/12'),
                 '-isystem', str(sdk / 'usr/aarch64-linux-gnu/include/c++/12/aarch64-linux-gnu')]
cxx.write_text('#!/bin/sh\nexec ' + shlex.join(cxx_arguments) + ' "$@"\n')
cxx.chmod(0o755)
stdlib = sdk / 'usr/lib/aarch64-linux-gnu/libstdc++.so'
if not stdlib.exists():
    stdlib.symlink_to('/usr/aarch64-linux-gnu/lib/libstdc++.so.6')
cross = base / 'cross.ini'
cross.write_text(f'''[binaries]
c = '{cc}'
cpp = '{cxx}'
ar = '/usr/bin/aarch64-linux-gnu-ar'
strip = '/usr/bin/aarch64-linux-gnu-strip'
pkg-config = '/usr/bin/pkg-config'
[host_machine]
system = 'linux'
cpu_family = 'aarch64'
cpu = 'armv8-a'
endian = 'little'
[properties]
needs_exe_wrapper = true
sys_root = '{sdk}'
pkg_config_libdir = ['{sdk}/usr/lib/aarch64-linux-gnu/pkgconfig', '{sdk}/usr/share/pkgconfig']
[built-in options]
c_link_args = ['-Wl,--allow-shlib-undefined']
cpp_link_args = ['-Wl,--allow-shlib-undefined']
''')
native = base / 'native.ini'
native.write_text(f'''[binaries]
c = '/usr/bin/gcc'
cpp = '/usr/bin/g++'
pkg-config = '/usr/bin/pkg-config'
[built-in options]
pkg_config_path = ['{native_pc}']
''')
build = base / 'build'
args = [str(venv / 'bin/meson'), 'setup', str(build), str(source),
        '--cross-file', str(cross), '--native-file', str(native),
        '--prefix=/usr/lib/sailfish-native', '--libdir=.', '--buildtype=release',
        '-Dc_args=-I' + str(sdk / 'usr/include') + ' -I' + str(sdk / 'usr/include/aarch64-linux-gnu'),
        '-Dcpp_args=-I' + str(sdk / 'usr/include') + ' -I' + str(sdk / 'usr/include/aarch64-linux-gnu'),
        *config['meson_options']]
if (build / 'meson-private/coredata.dat').exists():
    args.append('--reconfigure')
subprocess.run(args, env=env, check=True)
subprocess.run([str(venv / 'bin/meson'), 'compile', '-C', str(build),
                '-j', os.environ.get('SFOS_JOBS', '8')], env=env, check=True)
stage = base / 'stage'
subprocess.run([str(venv / 'bin/meson'), 'install', '-C', str(build), '--no-rebuild',
                '--skip-subprojects', '--destdir', str(stage)], env=env, check=True)
installed = stage / 'usr/lib/sailfish-native'
if payload.exists():
    shutil.rmtree(payload)
payload.mkdir()
for name in ['libEGL_mesa.so.0', 'libEGL_mesa.so.0.0.0', 'libgbm.so.1', 'libgbm.so.1.0.0',
             'libgallium-' + config['version'] + '.so']:
    path = installed / name
    if path.is_symlink():
        (payload / name).symlink_to(path.readlink())
    else:
        shutil.copy2(path, payload / name)
shutil.copytree(installed / 'gbm', payload / 'gbm', symlinks=True)
for path in payload.rglob('*'):
    if path.is_file() and not path.is_symlink() and path.read_bytes()[:4] == b'\x7fELF':
        subprocess.run(['patchelf', '--set-rpath', '/usr/lib/sailfish-native', str(path)], check=True)
(payload / 'MESA-LICENSE.txt').write_text((source / 'docs/license.rst').read_text())
(payload / 'MESA-BUILD.json').write_text(json.dumps(
    {'version': config['version'], 'source': config['source'], 'options': config['meson_options']},
    indent=2) + '\n')
files = {str(p.relative_to(payload)): sha256(p) for p in payload.rglob('*') if p.is_file() and not p.is_symlink()}
links = {str(p.relative_to(payload)): str(p.readlink()) for p in payload.rglob('*') if p.is_symlink()}
marker.write_text(json.dumps({'version': config['version'], 'source': config['source'],
                              'options': config['meson_options'], 'fingerprint': fingerprint,
                              'files': files, 'links': links}, indent=2) + '\n')
print('Built native Mesa', config['version'], 'with EGL_WL_bind_wayland_display')
