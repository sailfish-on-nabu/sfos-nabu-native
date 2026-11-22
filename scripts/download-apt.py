#!/usr/bin/env python3
"""Download an apt --print-uris plan into its archive cache."""
import concurrent.futures
import hashlib
import pathlib
import shlex
import sys
import time
import urllib.request

plan = pathlib.Path(sys.argv[1])
cache = pathlib.Path(sys.argv[2])
cache.mkdir(parents=True, exist_ok=True)
packages = [shlex.split(line) for line in plan.read_text().splitlines() if line.startswith("'")]


def download(fields):
    url, filename, length, checksum = fields
    destination = cache / filename
    algorithm, digest = checksum.split(":", 1)
    algorithm = algorithm.lower().replace("sum", "")
    def matches(path):
        return path.exists() and path.stat().st_size == int(length) and hashlib.new(algorithm, path.read_bytes()).hexdigest() == digest
    if matches(destination):
        return filename
    temporary = cache / (filename + ".download")
    for attempt in range(4):
        try:
            with urllib.request.urlopen(url.replace("http://", "https://", 1), timeout=120) as response, temporary.open("wb") as output:
                while block := response.read(1024 * 1024):
                    output.write(block)
            if not matches(temporary):
                raise ValueError("Package checksum mismatch for " + filename)
            temporary.replace(destination)
            return filename
        except Exception:
            if attempt == 3:
                raise
            time.sleep(attempt + 1)


with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
    for name in pool.map(download, packages):
        print(name, flush=True)
