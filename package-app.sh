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

# Ask SwiftPM for the product directory: its layout depends on the build
# system and toolchain. Avoid globs, which zsh rejects when they don't match.
# Require the resource bundle too, since a missing bundle crashes at launch.
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"
BIN_SRC="$BIN_DIR/BITTyping"
if [[ ! -f "$BIN_SRC" ]]; then
    echo "Error: BITTyping binary not found in '$BIN_DIR'." >&2
    exit 1
fi
BUNDLE_SRC="$BIN_DIR/BITTyping_BITTyping.bundle"
if [[ ! -d "$BUNDLE_SRC" ]]; then
    echo "Error: BITTyping_BITTyping.bundle not found in '$BIN_DIR'." >&2
    exit 1
fi

cp "$BIN_SRC" "$APP/Contents/MacOS/"
cp "Info.plist" "$APP/Contents/"
cp -R "$BUNDLE_SRC" "$APP/Contents/Resources/"
# NOTE: the bundle must live ONLY in Contents/Resources. A second copy next
# to the executable (Contents/MacOS/) breaks `codesign --deep` ("bundle
# format unrecognized, invalid, or unsuitable"), so don't add one — the app
# locates the Resources copy on its own.

BUNDLE_DEST="$APP/Contents/Resources/BITTyping_BITTyping.bundle"
if [[ ! -d "$BUNDLE_DEST/courses" && ! -d "$BUNDLE_DEST/Contents/Resources/courses" ]]; then
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
