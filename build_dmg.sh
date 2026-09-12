#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# This script is intended to live in the Swift project directory, or in an
# outputs folder directly below it.
if [[ -f "$SCRIPT_DIR/Package.swift" && -f "$SCRIPT_DIR/package-app.sh" ]]; then
    PROJECT_DIR="$SCRIPT_DIR"
elif [[ -f "$SCRIPT_DIR/../Package.swift" && -f "$SCRIPT_DIR/../package-app.sh" ]]; then
    PROJECT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
else
    echo "Error: put this script in the BIT Typing Swift project or its outputs folder." >&2
    exit 1
fi

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "Error: build_macos.sh must be run on macOS." >&2
    exit 1
fi

APP_NAME="BIT Typing"
APP_VERSION="${1:-2.0.0}"
SIGN_IDENTITY="${MACOS_SIGN_IDENTITY:--}"
OUTPUT_DIR="$PROJECT_DIR/outputs"

# package-app.sh is expected to create the application bundle here.
APP_PATH="$PROJECT_DIR/$APP_NAME.app"
OUTPUT_DMG="$OUTPUT_DIR/$APP_NAME-$APP_VERSION-macOS-$(uname -m).dmg"

if [[ ! "$APP_VERSION" =~ ^[0-9][0-9A-Za-z.+-]*$ ]]; then
    echo "Error: '$APP_VERSION' is not a valid application version." >&2
    exit 1
fi

for command_name in swift hdiutil ditto codesign osascript; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
        echo "Error: required command '$command_name' was not found." >&2
        exit 1
    fi
done

if [[ ! -f "$PROJECT_DIR/Package.swift" ]]; then
    echo "Error: '$PROJECT_DIR/Package.swift' is missing." >&2
    exit 1
fi

if [[ ! -x "$PROJECT_DIR/package-app.sh" ]]; then
    echo "Error: '$PROJECT_DIR/package-app.sh' is missing or not executable." >&2
    echo "Run: chmod +x '$PROJECT_DIR/package-app.sh'" >&2
    exit 1
fi

echo "Building $APP_NAME with Swift..."
cd "$PROJECT_DIR"

export BIT_TYPING_VERSION="$APP_VERSION"
if [[ -n "${MACOS_TARGET_ARCH:-}" ]]; then
    case "$MACOS_TARGET_ARCH" in
        arm64|x86_64)
            ;;
        universal2)
            echo "Warning: MACOS_TARGET_ARCH=universal2 is not handled by this script's Swift build." >&2
            echo "Build an appropriate Swift universal binary separately if required." >&2
            ;;
        *)
            echo "Error: MACOS_TARGET_ARCH must be arm64, x86_64, or universal2." >&2
            exit 1
            ;;
    esac
fi

swift build

echo "Packaging $APP_NAME.app..."
./package-app.sh

if [[ ! -d "$APP_PATH" ]]; then
    echo "Error: package-app.sh did not create '$APP_PATH'." >&2
    echo "Expected the packaged application at: $APP_PATH" >&2
    exit 1
fi

echo "Signing the application..."
if [[ "$SIGN_IDENTITY" == "-" ]]; then
    codesign --force --deep --sign - "$APP_PATH"
else
    codesign --force --deep --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP_PATH"
fi

codesign --verify --deep --strict --verbose=2 "$APP_PATH"

DMG_TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/bit-typing-dmg.XXXXXX")"
DMG_CONTENTS="$DMG_TEMP_ROOT/contents"
RW_DMG="$DMG_TEMP_ROOT/bit-typing-rw.dmg"
MOUNT_POINT=""

cleanup() {
    if [[ -n "$MOUNT_POINT" && -d "$MOUNT_POINT" ]]; then
        hdiutil detach "$MOUNT_POINT" -quiet || hdiutil detach "$MOUNT_POINT" -force -quiet || true
    fi
    rm -rf -- "$DMG_TEMP_ROOT"
}
trap cleanup EXIT

mkdir -p "$DMG_CONTENTS/.background"

# Use the packaged Swift application as the source app for the DMG.
ditto "$APP_PATH" "$DMG_CONTENTS/$APP_NAME.app"
ln -s /Applications "$DMG_CONTENTS/Applications"

# Keep the same DMG creation/layout flow as the original script.
# A small dark background and center arrow keep the DMG consistent with the
# application while retaining the familiar app-to-Applications layout.
if command -v sips >/dev/null 2>&1; then
    # No generated icon is required here: package-app.sh owns the application
    # icon. The DMG itself is created directly from the packaged .app.
    :
fi

python_background="$DMG_CONTENTS/.background/background.png"
if command -v swift >/dev/null 2>&1; then
    # Generate the background with CoreGraphics through a temporary Swift
    # program, avoiding any Python dependency in the build script.
    BACKGROUND_SWIFT="$DMG_TEMP_ROOT/make-background.swift"
    cat > "$BACKGROUND_SWIFT" <<'SWIFT'
import AppKit

let output = CommandLine.arguments[1]
let size = NSSize(width: 600, height: 360)

guard
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(size.width),
        pixelsHigh: Int(size.height),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bitmapFormat: [],
        bytesPerRow: 0,
        bitsPerPixel: 0
    )
else {
    exit(1)
}

NSGraphicsContext.saveGraphicsState()
guard let context = NSGraphicsContext(bitmapImageRep: rep) else {
    exit(1)
}
NSGraphicsContext.current = context

NSColor(calibratedRed: 11/255, green: 16/255, blue: 32/255, alpha: 1).setFill()
NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()

let panel = NSRect(x: 18, y: 18, width: 564, height: 324)
NSColor(calibratedRed: 18/255, green: 26/255, blue: 46/255, alpha: 1).setFill()
NSBezierPath(roundedRect: panel, xRadius: 26, yRadius: 26).fill()

NSColor(calibratedRed: 38/255, green: 52/255, blue: 81/255, alpha: 1).setStroke()
let border = NSBezierPath(roundedRect: panel, xRadius: 26, yRadius: 26)
border.lineWidth = 2
border.stroke()

NSColor(calibratedRed: 45/255, green: 212/255, blue: 191/255, alpha: 1).setStroke()
let line = NSBezierPath()
line.move(to: NSPoint(x: 252, y: 180))
line.line(to: NSPoint(x: 344, y: 180))
line.lineWidth = 12
line.lineCapStyle = .butt
line.stroke()

NSColor(calibratedRed: 45/255, green: 212/255, blue: 191/255, alpha: 1).setFill()
let arrow = NSBezierPath()
arrow.move(to: NSPoint(x: 344, y: 152))
arrow.line(to: NSPoint(x: 388, y: 180))
arrow.line(to: NSPoint(x: 344, y: 208))
arrow.close()
arrow.fill()

context.flushGraphics()
NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else {
    exit(1)
}
try! png.write(to: URL(fileURLWithPath: output))
SWIFT

    swiftc "$BACKGROUND_SWIFT" -o "$DMG_TEMP_ROOT/make-background" \
        -framework AppKit
    "$DMG_TEMP_ROOT/make-background" "$python_background"
else
    echo "Error: swift is required to generate the DMG background." >&2
    exit 1
fi

echo "Creating the drag-to-Applications disk image..."
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$DMG_CONTENTS" \
    -ov \
    -format UDRW \
    "$RW_DMG" >/dev/null

ATTACH_PLIST="$DMG_TEMP_ROOT/attach.plist"
hdiutil attach "$RW_DMG" -readwrite -noverify -noautoopen -plist > "$ATTACH_PLIST"

MOUNT_POINT="$(/usr/libexec/PlistBuddy -c 'Print :system-entities:0:mount-point' "$ATTACH_PLIST" 2>/dev/null || true)"

if [[ -z "$MOUNT_POINT" || ! -d "$MOUNT_POINT" ]]; then
    # Fall back to parsing the plist with plutil if the first entity was not
    # the mounted volume.
    MOUNT_POINT="$(
        /usr/libexec/PlistBuddy -c 'Print :system-entities' "$ATTACH_PLIST" 2>/dev/null |
        awk -F'= ' '/mount-point/ {print $2; exit}' |
        sed 's/^"//; s/"$//'
    )"
fi

if [[ -z "$MOUNT_POINT" || ! -d "$MOUNT_POINT" ]]; then
    echo "Error: the temporary DMG could not be mounted." >&2
    exit 1
fi

if command -v SetFile >/dev/null 2>&1; then
    SetFile -a C "$MOUNT_POINT" || true
fi

MOUNT_NAME="$(basename "$MOUNT_POINT")"
if ! osascript - "$MOUNT_NAME" <<'APPLESCRIPT'
on run argv
    set volumeName to item 1 of argv
    tell application "Finder"
        tell disk volumeName
            open
            set current view of container window to icon view
            set toolbar visible of container window to false
            set statusbar visible of container window to false
            set the bounds of container window to {120, 120, 720, 480}
            set viewOptions to the icon view options of container window
            set arrangement of viewOptions to not arranged
            set icon size of viewOptions to 112
            set text size of viewOptions to 14
            set background picture of viewOptions to file ".background:background.png"
            set position of item "BIT Typing.app" of container window to {155, 180}
            set position of item "Applications" of container window to {445, 180}
            update without registering applications
            delay 2
            close
        end tell
    end tell
end run
APPLESCRIPT
then
    echo "Warning: Finder layout customization was skipped; the DMG is still installable." >&2
fi

sync
hdiutil detach "$MOUNT_POINT" -quiet
MOUNT_POINT=""

mkdir -p "$OUTPUT_DIR"
hdiutil convert "$RW_DMG" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -ov \
    -o "$OUTPUT_DMG" >/dev/null

hdiutil verify "$OUTPUT_DMG" >/dev/null

if [[ -n "${MACOS_NOTARY_PROFILE:-}" ]]; then
    if [[ "$SIGN_IDENTITY" == "-" ]]; then
        echo "Error: notarization requires MACOS_SIGN_IDENTITY to be a Developer ID Application certificate." >&2
        exit 1
    fi

    echo "Submitting the DMG for Apple notarization..."
    xcrun notarytool submit "$OUTPUT_DMG" --keychain-profile "$MACOS_NOTARY_PROFILE" --wait
    xcrun stapler staple "$OUTPUT_DMG"
fi

echo
echo "macOS installer created successfully:"
echo "  $OUTPUT_DMG"
echo

if [[ "$SIGN_IDENTITY" == "-" ]]; then
    echo "The app is ad-hoc signed. For public distribution, set MACOS_SIGN_IDENTITY"
    echo "and optionally MACOS_NOTARY_PROFILE before running this script."
fi
