#!/usr/bin/env python3
"""Compare the installed Sailfish RPM database with the requested release list."""

import argparse
import json
from pathlib import Path


def normalize(line):
    name, version = line.strip().split(maxsplit=1)
    if version.startswith("0:"):
        version = version[2:]
    return name, version


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("expected", type=Path)
    parser.add_argument("installed", type=Path)
    parser.add_argument("report", type=Path)
    parser.add_argument("--exclude", type=Path)
    parser.add_argument("--native-package", action="append", default=[])
    args = parser.parse_args()
    reference = dict(normalize(line) for line in args.expected.read_text().splitlines() if line.strip())
    excluded_names = set(args.exclude.read_text().splitlines()) if args.exclude else set()
    excluded = {name: version for name, version in reference.items() if name.rsplit(".", 1)[0] in excluded_names}
    expected = {name: version for name, version in reference.items() if name not in excluded}
    installed = dict(
        normalize(line)
        for line in args.installed.read_text().splitlines()
        if line.split() and line.split()[0].endswith((".aarch64", ".noarch"))
    )
    missing = sorted(set(expected) - set(installed))
    mismatched = [
        {"name": name, "expected": version, "installed": installed[name]}
        for name, version in expected.items()
        if name in installed and installed[name] != version
    ]
    native_packages = {name: installed[name] for name in args.native_package if name in installed}
    missing_native = sorted(set(args.native_package) - set(installed))
    excluded_installed = sorted(name for name in installed if name.rsplit(".", 1)[0] in excluded_names)
    extra = sorted(set(installed) - set(expected) - set(args.native_package))
    report = {
        "reference_count": len(reference),
        "excluded_count": len(excluded),
        "excluded": excluded,
        "requested_count": len(expected),
        "installed_count": len(installed),
        "native_packages": native_packages,
        "missing_native_packages": missing_native,
        "excluded_still_installed": excluded_installed,
        "missing": missing,
        "version_mismatches": mismatched,
        "extra": extra,
        "complete": not missing and not mismatched and not missing_native and not excluded_installed and not extra,
    }
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))
    if not report["complete"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
