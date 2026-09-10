import SwiftUI

// MARK: - Working with the Monochrome Palette

/// Monochrome black foundation with a single functional blue accent.
///
/// Light mode: near-black ink on Apple grouped grays.
/// Dark mode: white ink on near-black groups.
/// Blue (`brand`) is reserved for live progress, links, the overall-score
/// gauge, and the active-character outline — everything else stays grayscale
/// so lesson text keeps the visual focus. Typing errors keep one muted
/// system red, matching the original app.
struct Theme {

    // MARK: - Reading Adaptive Colors

    static func background(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(nsColor: .windowBackgroundColor) : Color(red: 0.961, green: 0.961, blue: 0.969)
    }

    static func panel(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(nsColor: .controlBackgroundColor) : .white
    }

    static func panel2(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(nsColor: .separatorColor).opacity(0.45) : Color(red: 0.910, green: 0.910, blue: 0.929)
    }

    static func ink(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? .white : Color(red: 0.114, green: 0.114, blue: 0.122)
    }

    static func muted(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(nsColor: .secondaryLabelColor) : Color(red: 0.431, green: 0.431, blue: 0.451)
    }

    static func border(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(nsColor: .separatorColor) : Color(red: 0.824, green: 0.824, blue: 0.839)
    }

    static func pending(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(nsColor: .tertiaryLabelColor) : Color(red: 0.682, green: 0.682, blue: 0.698)
    }

    static func keycap(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(nsColor: .controlColor) : .white
    }

    /// Single functional blue accent (light `#007AFF`, dark `#0A84FF`).
    static func brand(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.039, green: 0.518, blue: 1.0) : Color(red: 0.0, green: 0.478, blue: 1.0)
    }

    static func error(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 1.0, green: 0.271, blue: 0.227) : Color(red: 0.843, green: 0.0, blue: 0.082)
    }

    static func errorTimeout(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.85, green: 0.2, blue: 0.18) : Color(red: 0.647, green: 0.0, blue: 0.0)
    }
}

// MARK: - Environment
//
// Colors resolve through `@Environment(\.colorScheme)` at each call site
// (e.g. `Theme.panel(scheme)`), so Light and Dark stay in normal SwiftUI
// resolution with no hardcoded light-only fills. Prescriptive overrides
// (card backgrounds, gauge tints) flow through dedicated `@Entry`
// environment values — see `Components.swift` — with the closest modifier
// winning and the theme as fallback.
//
// Deliberate AppKit boundaries (not SwiftUI-replaceable today):
// - `Color(nsColor:)` dynamic system colors for window/control surfaces.
// - `KeyCaptureView` (`NSViewRepresentable` + `NSEvent` monitors) for
//   window-level typing capture that keeps working after toolbar buttons
//   take focus; `.onKeyPress` alone loses events in that case.
// - `SoundService` (`AVFoundation`) for polyphonic key clicks; SwiftUI
//   has no audio primitive.
// - `NSImage.bitAppIcon` brand-icon loading shared by top bar/setup/about.
