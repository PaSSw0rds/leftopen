#!/usr/bin/env python3
"""Set release metadata in the CI checkout."""

import argparse
import plistlib
import re
from pathlib import Path


def version_tuple(value):
    if not re.fullmatch(r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)", value):
        raise ValueError("Use a stable version such as 0.4.1 (without v).")
    return tuple(map(int, value.split(".")))


def prepare(root, version, build, latest):
    if version_tuple(version) <= version_tuple(latest.removeprefix("v")):
        raise ValueError(f"Version must be newer than the latest release ({latest}).")
    plist_path = root / "Resources/Info.plist"
    cli_path = root / "Sources/LeftOpenCLI/main.swift"
    metadata = plistlib.loads(plist_path.read_bytes())
    if build <= int(metadata["CFBundleVersion"]):
        raise ValueError("Build number must be newer than the source build number.")
    source, count = re.subn(
        r'print\("LeftOpen [0-9]+\.[0-9]+\.[0-9]+"\)',
        f'print("LeftOpen {version}")', cli_path.read_text(),
    )
    if count != 1:
        raise ValueError("Expected exactly one CLI version declaration.")
    metadata["CFBundleShortVersionString"] = version
    metadata["CFBundleVersion"] = str(build)
    plist_path.write_bytes(plistlib.dumps(metadata, sort_keys=False))
    cli_path.write_text(source)
    print(f"Prepared LeftOpen {version} (build {build}), App and CLI.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("version")
    parser.add_argument("build", type=int)
    parser.add_argument("--latest", required=True)
    args = parser.parse_args()
    try:
        prepare(Path(__file__).resolve().parent.parent, args.version, args.build, args.latest)
    except ValueError as error:
        parser.error(str(error))
