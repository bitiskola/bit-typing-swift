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

# Prepare toolchain fixes for CommandLineTools manifest & bridging header bugs
FIX_DIR="$(pwd)/.build/manifest-fix"
if [[ ! -d "$FIX_DIR/ManifestAPI" ]]; then
    mkdir -p "$FIX_DIR/ManifestAPI"
    CLT_MANIFEST_DIR="$(xcode-select -p)/usr/lib/swift/pm/ManifestAPI"
    if [[ -d "$CLT_MANIFEST_DIR" ]]; then
        cp -R "$CLT_MANIFEST_DIR"/* "$FIX_DIR/ManifestAPI/"
        rm -f "$FIX_DIR/ManifestAPI"/PackageDescription.swiftmodule/*.private.swiftinterface
    fi
fi
if [[ ! -f "$FIX_DIR/vfs.yaml" ]]; then
    mkdir -p "$FIX_DIR"
    touch "$FIX_DIR/empty.modulemap"
    cat > "$FIX_DIR/vfs.yaml" <<EOF
{
  "version": 0,
  "case-sensitive": "false",
  "roots": [
    {
      "type": "directory",
      "name": "$(xcode-select -p)/usr/include/swift",
      "contents": [
        {
          "type": "file",
          "name": "bridging.modulemap",
          "external-contents": "$FIX_DIR/empty.modulemap"
        }
      ]
    }
  ]
}
EOF
fi

export SWIFTPM_CUSTOM_LIBS_DIR="$FIX_DIR"
EXTRA_SWIFTC_FLAGS=()
if [[ -f "$FIX_DIR/vfs.yaml" ]]; then
    EXTRA_SWIFTC_FLAGS=("-Xswiftc" "-vfsoverlay" "-Xswiftc" "$FIX_DIR/vfs.yaml")
fi

CONFIG=release
if [[ "${1:-}" == "--debug" ]]; then CONFIG=debug; fi

swift build -c "$CONFIG" "${EXTRA_SWIFTC_FLAGS[@]}"

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
if [[ ! -d "$BUNDLE_DEST/default-repo" && ! -d "$BUNDLE_DEST/Contents/Resources/default-repo" ]]; then
    echo "Error: resource bundle copy failed — default-repo/ missing in $APP/Contents/Resources/." >&2
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
