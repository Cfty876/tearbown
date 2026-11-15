"""Generate the website update manifest from the finished release archives."""

import argparse
import hashlib
import json
from pathlib import Path
import re
import zipfile


def release_asset(archive, tag, filename, entry, notarized=None):
    with zipfile.ZipFile(archive) as bundle:
        if entry not in bundle.namelist():
            raise ValueError(f"{archive}: missing {entry}")
    checksum = hashlib.sha256()
    with archive.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            checksum.update(block)
    asset = {
        "url": f"https://github.com/Cfty876/tearbown/releases/download/{tag}/{filename}",
        "size": archive.stat().st_size,
        "sha256": checksum.hexdigest(),
    }
    if notarized is not None:
        asset["notarized"] = notarized
    return asset


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("version")
    parser.add_argument("--windows", type=Path, required=True)
    parser.add_argument("--macos", type=Path, required=True)
    parser.add_argument("--macos-notarized", action="store_true")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if not re.fullmatch(r"(?:0|[1-9][0-9]{0,3})(?:\.(?:0|[1-9][0-9]{0,3})){2}", args.version):
        parser.error("expected a release version, for example 1.1.0")
    tag = "breakpoint-v" + args.version
    manifest = {
        "version": args.version,
        "tag": tag,
        "platforms": {
            "windows": release_asset(args.windows, tag, "BREAKPOINT-Windows-x64.zip", "BREAKPOINT.exe"),
            "macos": release_asset(args.macos, tag, "BREAKPOINT-macOS.zip",
                                   "BREAKPOINT.app/Contents/MacOS/BREAKPOINT", args.macos_notarized),
        },
    }
    args.output.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
