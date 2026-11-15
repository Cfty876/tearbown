"""Copy the Godot inputs used by a Windows, macOS or browser release."""

import argparse
from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "game"
OLD_POLICIES = {
    "school_hide_policy.tres", "school_maneuvers.tres",
    "school_pursuit_policy.tres", "school_rl_policy.tres",
}
PLAYER_DIRS = ("audio", "scenes", "scripts", "shaders", "ui")
CONFIGS = ("project.godot", "voxcore.gdextension", "voxcore.gdextension.uid", "export_presets.cfg")


def ignore_assets(_directory, names):
    return [name for name in names if (
        name in OLD_POLICIES or name in {"__pycache__", ".DS_Store"} or
        name.endswith((".mp3", ".mp3.import", ".bak", ".tmp"))
    )]


def stage(destination, platform, relay):
    destination = destination.resolve()
    if destination == ROOT or destination.is_relative_to(SOURCE):
        raise ValueError("Use an empty staging directory outside game/")
    if destination.exists() and (not destination.is_dir() or any(destination.iterdir())):
        raise ValueError("The staging directory must be empty")
    destination.mkdir(parents=True, exist_ok=True)
    for name in CONFIGS:
        shutil.copy2(SOURCE / name, destination / name)
    project = destination / "project.godot"
    settings = project.read_text(encoding="utf-8-sig")
    settings = settings.replace('config/name="Voxel Teardown Prototype"', 'config/name="BREAKPOINT"')
    settings = settings.replace('Fully destructible voxel physics sandbox prototype.', 'Voxel sandbox and multiplayer hide-and-seek.')
    project.write_text(settings, encoding="utf-8")
    for name in PLAYER_DIRS:
        shutil.copytree(SOURCE / name, destination / name, ignore=ignore_assets)
    (destination / "bin").mkdir()

    if platform == "windows":
        addon = SOURCE / "addons" / "nobodywho"
        if any(addon.glob("*.dll")):
            shutil.copytree(addon, destination / "addons" / "nobodywho",
                            ignore=shutil.ignore_patterns("*.pdb", "*.bak"))
    elif platform == "web":
        shutil.copy2(ROOT / "web" / "shell.html", destination / "ui" / "web_shell.html")
    if relay and platform != "web":
        (destination / "online.cfg").write_text(
            '[online]\nurl="' + relay + '"\n', encoding="utf-8"
        )


if __name__ == "__main__":
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument("platform", choices=("windows", "macos", "web"))
    cli.add_argument("destination", type=Path)
    cli.add_argument("--relay", default="")
    args = cli.parse_args()
    if args.relay and (not args.relay.startswith("wss://") or any(c in args.relay for c in '"\r\n')):
        cli.error("Relay must be a WSS URL")
    stage(args.destination, args.platform, args.relay)
