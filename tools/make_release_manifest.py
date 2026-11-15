"""Generate the website update manifest from the finished release archives."""

import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import zipfile


VERSION = re.compile(r"(?:0|[1-9][0-9]{0,3})(?:\.(?:0|[1-9][0-9]{0,3})){2}")
WINDOWS_FILES = {
    "BREAKPOINT.exe", "BREAKPOINT.pck", "voxcore.dll",
    "libnobodywho-godot-x86_64-pc-windows-msvc-release.dll",
    "COPYRIGHT-Godot.txt", "LICENSE-Godot.txt", "LICENSE-NobodyWho.txt",
}


def release_asset(archive, tag, filename, entry, notarized=None):
    with zipfile.ZipFile(archive) as bundle:
        if entry not in bundle.namelist():
            raise ValueError(f"{archive}: missing {entry}")
    asset = {
        "url": f"https://github.com/Cfty876/tearbown/releases/download/{tag}/{filename}",
        "size": archive.stat().st_size,
        "sha256": archive_digest(archive),
    }
    if notarized is not None:
        asset["notarized"] = notarized
    return asset


def archive_digest(archive):
    with archive.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def windows_inventory(bundle):
    entries = [entry.filename for entry in bundle.infolist() if not entry.is_dir()]
    if len(set(entries)) != len(entries) or not set(entries) <= WINDOWS_FILES:
        raise ValueError("Windows archive contains unexpected paths")
    result = {}
    for entry in entries:
        with bundle.open(entry) as stream:
            result[entry] = hashlib.file_digest(stream, "sha256").hexdigest()
    return result


def windows_patch(base, current, current_files, tag, version, directory):
    with zipfile.ZipFile(base) as previous, zipfile.ZipFile(current) as release:
        old_files = windows_inventory(previous)
        if not old_files.keys() <= current_files.keys():
            # A ZIP overlay cannot remove files from a previous release.
            return None
        requires = {name: sha for name, sha in current_files.items() if old_files.get(name) == sha}
        changed = sorted(current_files.keys() - requires.keys())
        if "BREAKPOINT.exe" not in old_files or not changed or not requires:
            return None
        name = f"BREAKPOINT-Windows-x64-from-{version}.zip"
        output = directory / name
        if output.resolve() in {current.resolve(), base.resolve()}:
            raise ValueError("Patch output would overwrite an input archive")
        with zipfile.ZipFile(output, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as patch:
            for entry in changed:
                with release.open(entry) as source, patch.open(entry, "w") as target:
                    shutil.copyfileobj(source, target)
    if output.stat().st_size >= current.stat().st_size:
        output.unlink()
        return None
    info = release_asset(output, tag, name, changed[0])
    info["requires"] = requires
    return info


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("version")
    parser.add_argument("--windows", type=Path, required=True)
    parser.add_argument("--macos", type=Path, required=True)
    parser.add_argument("--macos-notarized", action="store_true")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--windows-base", action="append", default=[], metavar="VERSION=ZIP")
    parser.add_argument("--patch-dir", type=Path)
    args = parser.parse_args()
    if not VERSION.fullmatch(args.version):
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
    if args.windows_base:
        if args.patch_dir is None:
            parser.error("--windows-base requires --patch-dir")
        args.patch_dir.mkdir(parents=True, exist_ok=True)
        with zipfile.ZipFile(args.windows) as release:
            current_files = windows_inventory(release)
        patches = {}
        seen_versions = set()
        for spec in args.windows_base:
            before, separator, path = spec.partition("=")
            if (not separator or not path or not VERSION.fullmatch(before)
                    or tuple(map(int, before.split("."))) >= tuple(map(int, args.version.split(".")))
                    or before in seen_versions):
                parser.error("--windows-base expects a unique earlier version and ZIP path")
            seen_versions.add(before)
            info = windows_patch(Path(path), args.windows, current_files, tag, before, args.patch_dir)
            if info is not None:
                patches[before] = info
        if patches:
            manifest["platforms"]["windows"]["patches"] = patches
    args.output.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
