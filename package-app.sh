#!/bin/zsh
# Packages BITTyping as a proper macOS .app bundle.
#
# A bare binary has no bundle identifier, which makes macOS system services
# (intents/linkd, process registry, window-tab indexing) log errors at
# launch. This script produces BITTyping.app with an Info.plist, icon, and
# the SwiftPM resource bundle, so those errors go away.
#
# Usage: ./package-app.sh [--debug]
set -euo pipefail
cd "$(dirname "$0")"

CONFIG=release
if [[ "${1:-}" == "--debug" ]]; then CONFIG=debug; fi

swift build -c "$CONFIG"

APP="BIT Typing.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# Locate build products robustly: newer toolchains put them under
# .build/<triple>/<config>/ with .build/<config> as a symlink, and the
# triple varies (x86_64 vs arm64). Fail loudly instead of shipping an app
# whose resource bundle is missing (that used to crash at launch via a
# Bundle.module fatalError on any machine other than the build host).
BIN_SRC=""
for CAND in ".build/$CONFIG/BITTyping" .build/*/"$CONFIG"/BITTyping; do
    if [[ -f "$CAND" ]]; then BIN_SRC="$CAND"; break; fi
done
if [[ -z "$BIN_SRC" ]]; then
    echo "Error: BITTyping binary not found under .build/ for config '$CONFIG'." >&2
    exit 1
fi
BUNDLE_SRC=""
for CAND in ".build/$CONFIG/BITTyping_BITTyping.bundle" .build/*/"$CONFIG"/BITTyping_BITTyping.bundle; do
    if [[ -d "$CAND" ]]; then BUNDLE_SRC="$CAND"; break; fi
done
if [[ -z "$BUNDLE_SRC" ]]; then
    echo "Error: BITTyping_BITTyping.bundle not found under .build/ for config '$CONFIG'." >&2
    exit 1
fi

cp "$BIN_SRC" "$APP/Contents/MacOS/"
cp "Info.plist" "$APP/Contents/"
cp -R "$BUNDLE_SRC" "$APP/Contents/Resources/"
# NOTE: the bundle must live ONLY in Contents/Resources. A second copy next
# to the executable (Contents/MacOS/) breaks `codesign --deep` ("bundle
# format unrecognized, invalid, or unsuitable"), so don't add one — the app
# locates the Resources copy on its own.

if [[ ! -d "$APP/Contents/Resources/BITTyping_BITTyping.bundle/courses" ]]; then
    echo "Error: resource bundle copy failed — courses/ missing in $APP/Contents/Resources/." >&2
    exit 1
fi

# Real Dock/Finder icon generated from the bundled favico.png.
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
for SIZE in 16 32 64 128 256 512; do
    sips -z "$SIZE" "$SIZE" "Sources/BITTyping/Resources/favico.png" --out "$ICONSET/icon_${SIZE}x${SIZE}.png" >/dev/null
    sips -z "$((SIZE * 2))" "$((SIZE * 2))" "Sources/BITTyping/Resources/favico.png" --out "$ICONSET/icon_${SIZE}x${SIZE}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$(dirname "$ICONSET")"

# Ad-hoc signature so Gatekeeper treats the local build kindly.
codesign --force --deep --sign - "$APP" 2>/dev/null || true

echo "Built $APP — open it with: open \"$APP\""
