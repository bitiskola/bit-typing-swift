# BIT Typing (macOS, SwiftUI)

Native macOS port of the BIT Typing tutor. Same lessons and engine
behavior as the Python app, SwiftUI interface.

## Requirements

- Apple Silicon (For x86 use the Rust version!) macOS 14+ to run (Liquid Glass details light up on macOS 26)
- Swift 6 toolchain (Xcode 26 or Command Line Tools)

## Build and run

```bash
swift build
swift run BITTyping

# Self-contained BIT Typing.app bundle with Dock icon:
./package-app.sh
open "BIT Typing.app"

# Headless engine self-test (typing modes, backspace rules, scoring):
swift run BITTyping --verify-engine
```

## Installer disk image

```bash
./package-dmg.sh
```

Rebuilds the app, then produces `BIT Typing-1.0.0-macOS-arm64.dmg`:
drag-and-drop install (app + `Applications` link) with the app icon
as the volume icon and the Finder icon positions baked in. Requires
Xcode Command Line Tools (`hdiutil`, `osascript`, `SetFile`).

## Layouts, lessons, languages

Keyboard layouts live in `Sources/BITTyping/Resources/keyboards/`
(`HU-qwertz.json`, `US-qwerty.json`). Each file defines `rows`
(number row first) plus a `space_label`:

```json
{
  "name": "Hungarian QWERTZ",
  "rows": [["0", "1", ...], ["q", "w", ...], ["a", "s", ...], ["í", ...]],
  "space_label": "SZÓKÖZ"
}
```

Lessons are plain `.txt` files in `Resources/courses/`, language
strings in `Resources/lang/` (`EN-us.json`, `HU-hu.json`).
Placeholders use `{name}` or Python-style `{name:format}`;
values arrive pre-formatted.

Custom lessons can be added from the Lesson editor tab or by
dropping `.txt` files into the courses folder (see below).

## Data

Writable root: `~/Library/Application Support/BIT Typing/`
(`courses/`, `lang/`, `keyboards/`, `data/` with `settings.json`,
`history.json`, `custom_courses.json`).

On first launch the bundled defaults are copied there. Language,
keyboard, and sound files refresh from the bundle on every launch;
courses are seeded once and never overwritten. `settings.json`
stays compatible with the Python app.
