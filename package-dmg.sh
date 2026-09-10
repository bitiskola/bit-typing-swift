#!/bin/zsh
# Builds a clean, installable BIT Typing DMG:
# BIT Typing.app + Applications symlink, custom volume icon,
# Finder icon layout baked in. No background image.
#
# Usage: ./package-dmg.sh
set -euo pipefail
cd "$(dirname "$0")"

VERSION="1.0.0"
APP="BIT Typing.app"
VOL="BIT Typing"
DMG="BIT Typing-${VERSION}-macOS-arm64.dmg"
STAGING="$(mktemp -d)/staging"

# Fresh app bundle first.
./package-app.sh

rm -rf "$STAGING" "$DMG" "tmp-${VOL}.dmg"
hdiutil detach "/Volumes/$VOL" >/dev/null 2>&1 || true
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

# Custom volume icon (hidden .VolumeIcon.icns + custom bit on the folder).
cp "$STAGING/$APP/Contents/Resources/AppIcon.icns" "$STAGING/.VolumeIcon.icns"
SetFile -a V "$STAGING/.VolumeIcon.icns"
SetFile -a C "$STAGING"

hdiutil create -size 220m -format UDRW -volname "$VOL" -srcfolder "$STAGING" -ov "tmp-${VOL}.dmg" >/dev/null
rm -rf "$STAGING"

DEVICE=$(hdiutil attach -readwrite -noverify "tmp-${VOL}.dmg" | grep -E '^/dev/' | head -1 | awk '{print $1}')

osascript <<APPLESCRIPT
tell application "Finder"
    open disk "$VOL"
    delay 2
    tell front Finder window
        set current view to icon view
        set toolbar visible to false
        set statusbar visible to false
        set the bounds to {200, 120, 960, 600}
        set arrangement of its icon view options to not arranged
        set icon size of its icon view options to 128
        set position of item "$APP" to {190, 250}
        set position of item "Applications" to {570, 250}
    end tell
    delay 1
    close container window of disk "$VOL"
    open disk "$VOL"
    update disk "$VOL" without registering applications
    delay 2
end tell
APPLESCRIPT

SetFile -a C "/Volumes/$VOL"
sync
hdiutil detach "$DEVICE" >/dev/null
hdiutil convert "tmp-${VOL}.dmg" -format UDZO -imagekey zlib-level=9 -o "$DMG" >/dev/null
rm -f "tmp-${VOL}.dmg"

echo "Built $DMG"
