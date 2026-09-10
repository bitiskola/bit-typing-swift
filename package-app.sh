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

cp ".build/$CONFIG/BITTyping" "$APP/Contents/MacOS/"
cp "Info.plist" "$APP/Contents/"
cp -R ".build/$CONFIG/BITTyping_BITTyping.bundle" "$APP/Contents/Resources/"

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
