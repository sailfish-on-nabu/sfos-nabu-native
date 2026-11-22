#!/usr/bin/env python3
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import urllib.request

manifest, cache = map(Path, sys.argv[1:])
cache.mkdir(parents=True, exist_ok=True)
data = json.loads(manifest.read_text())
archives = []
for package in data['packages']:
    path = cache / package['name']
    if not path.exists() or hashlib.sha256(path.read_bytes()).hexdigest() != package['sha256']:
        temp = path.with_suffix('.download')
        with urllib.request.urlopen(package['url'], timeout=60) as response:
            temp.write_bytes(response.read())
        if hashlib.sha256(temp.read_bytes()).hexdigest() != package['sha256']:
            raise SystemExit(f'Camera build header checksum mismatch: {package["name"]}')
        temp.replace(path)
    archives.append(path)
headers = cache / 'headers'
digest = hashlib.sha256(manifest.read_bytes()).hexdigest()
marker = cache / 'headers.manifest'
if not marker.exists() or marker.read_text() != digest:
    if headers.exists():
        shutil.rmtree(headers)
    headers.mkdir()
    for archive in archives:
        subprocess.run(['dpkg-deb', '-x', str(archive), str(headers)], check=True)
    marker.write_text(digest)
