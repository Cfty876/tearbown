#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")" && pwd)"
[[ "$(uname -s)" == Darwin ]] || { printf '%s\n' 'Run this script on macOS.' >&2; exit 2; }
: "${GODOT_BIN:?Set GODOT_BIN to the Godot 4.7.2 editor executable}"
if [[ $# != 1 ]]; then printf '%s\n' 'Usage: bash build_macos.sh <empty output directory>' >&2; exit 2; fi
mkdir -p "$1"
out="$(cd "$1" && pwd)"
[[ -z "$(ls -A "$out")" ]] || { printf '%s\n' 'Choose an empty output directory.' >&2; exit 2; }

python3 "$root/tools/stage_release.py" macos "$out/project" --relay "${BREAKPOINT_RELAY_URL:-}"
cmake -S "$root/native" -B "$out/native" -DCMAKE_BUILD_TYPE=Release \
  "-DCMAKE_OSX_ARCHITECTURES=arm64;x86_64" -DCMAKE_OSX_DEPLOYMENT_TARGET=12.0 \
  "-DGODOTCPP_BUILD_PROFILE=$root/native/web-profile.json"
cmake --build "$out/native" --config Release --target voxcore --parallel 4
lib="$out/native/out/libvoxcore.dylib"
lipo -verify_arch arm64 x86_64 "$lib"
cp "$lib" "$out/project/bin/libvoxcore.dylib"
"$GODOT_BIN" --headless --editor --path "$out/project" --import --quit
app="$out/BREAKPOINT.app"
"$GODOT_BIN" --headless --path "$out/project" --export-release macOS "$app"
lipo -verify_arch arm64 x86_64 "$app/Contents/MacOS/BREAKPOINT"

notarized=0
if [[ -n "${BREAKPOINT_CODESIGN_ID:-}" && -n "${BREAKPOINT_NOTARY_PROFILE:-}" ]]; then
  identity="$BREAKPOINT_CODESIGN_ID"
  options=(--timestamp --options runtime)
  notarized=1
else
  identity=-
  options=(--timestamp=none)
fi
while IFS= read -r -d '' library; do
  codesign --force --sign "$identity" "${options[@]}" "$library"
done < <(find "$app/Contents" -type f -name '*.dylib' -print0)
codesign --force --sign "$identity" "${options[@]}" "$app"
codesign --verify --deep --strict "$app"

if [[ "$notarized" == 1 ]]; then
  ditto -c -k --keepParent "$app" "$out/notarization.zip"
  xcrun notarytool submit "$out/notarization.zip" --keychain-profile "$BREAKPOINT_NOTARY_PROFILE" --wait
  xcrun stapler staple "$app"
  xcrun stapler validate "$app"
  spctl --assess --type execute "$app"
  ditto -c -k --keepParent "$app" "$out/BREAKPOINT-macOS-universal.zip"
else
  ditto -c -k --keepParent "$app" "$out/BREAKPOINT-macOS-test.zip"
  printf '%s\n' 'Internal test build. Public distribution needs Developer ID and notarization.' >&2
fi
