#!/usr/bin/env python3
import hashlib
import json
import pathlib
import sys
import urllib.request

project = pathlib.Path(sys.argv[1])
work = pathlib.Path(sys.argv[2])
destination = work / "downloads"
destination.mkdir(parents=True, exist_ok=True)


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(4 * 1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


for item in json.loads((project / "inputs/downloads.json").read_text()):
    target = destination / item["filename"]
    if target.exists() and sha256(target) == item["sha256"]:
        print("Verified", target.name, flush=True)
        continue
    temporary = target.with_name(target.name + ".partial")
    with urllib.request.urlopen(item["url"], timeout=120) as response, temporary.open("wb") as output:
        while block := response.read(1024 * 1024):
            output.write(block)
    if sha256(temporary) != item["sha256"]:
        raise ValueError("Checksum mismatch for " + target.name)
    temporary.replace(target)
    print("Downloaded", target.name, flush=True)
rootfs = json.loads((project / "inputs/sailfish-rootfs.json").read_text())
if sha256(pathlib.Path(rootfs["path"])) != rootfs["sha256"]:
    raise ValueError("The local Sailfish rootfs archive has changed")
print("Verified local Sailfish rootfs", flush=True)
