import AppKit
import SwiftUI

// MARK: - Showing Lesson Text

/// Pinned lesson strip, ported from `lesson_text_pinned` in the Rust
/// version. Completed text sits left, upcoming text right, and the active
/// character is held in the exact middle of the viewport. On every
/// character switch the strip glides there (~0.12s ease-out) and the active
/// cell pops (1.18x → 1.0 over ~0.14s), so each keystroke stays visible
/// even at speed.
struct LessonTextView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var text: String
    var states: [Int: CharState]
    var activeIndex: Int

    var body: some View {
        // Convert once: indexing a String per cell would reconvert it for
        // every one of the ~240 visible cells on each keystroke.
        let chars = Array(text)
        let offsets = Self.visibleOffsets(count: chars.count, active: activeIndex)
        let cell = Self.cellWidth
        let hasActive = activeIndex < chars.count
        let activeWidth = hasActive ? cell + CharacterCell.activePadding * 2 : 0
        // Every cell is exactly `cell` wide (the active one adds padding),
        // so positions are pure arithmetic in lesson-absolute coordinates:
        // the strip keeps moving on every keystroke, even after the cell
        // window starts sliding along a long lesson.
        let anchor = CGFloat(min(activeIndex, chars.count)) * cell + activeWidth / 2
        let lead = CGFloat(offsets.first ?? 0) * cell
        return GeometryReader { proxy in
            HStack(spacing: 0) {
                Color.clear.frame(width: lead, height: 1)
                ForEach(offsets, id: \.self) { offset in
                    CharacterCell(
                        char: chars[offset],
                        state: states[offset],
                        isActive: offset == activeIndex,
                        width: cell
                    )
                    .equatable()
                }
            }
            .fixedSize()
            .offset(x: proxy.size.width / 2 - anchor)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .leading)
            .animation(reduceMotion ? nil : Self.glide, value: activeIndex)
        }
        .clipped()
        // VoiceOver reads the lesson as one adjustable value instead of
        // reconstructing meaning from individual cells.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Lesson text"))
        .accessibilityValue(Text(accessibilityProgress(count: chars.count)))
    }

    // MARK: - Private

    /// Cubic ease-out over 0.12s, the curve the Rust port uses.
    private static let glide = Animation.timingCurve(0.33, 1, 0.68, 1, duration: 0.12)

    static let fontSize: CGFloat = 44

    /// Advance of one glyph in the lesson font (monospaced, so every
    /// character shares it).
    static let cellWidth: CGFloat = {
        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .medium)
        return ceil(("M" as NSString).size(withAttributes: [.font: font]).width)
    }()

    /// Visible window around the cursor. Keeps ~80 finished chars on the
    /// left and ~160 upcoming chars on the right so long lessons stay at
    /// a flat view count instead of growing with lesson length.
    private static func visibleOffsets(count: Int, active: Int) -> [Int] {
        guard count > 0 else { return [] }
        let cursor = min(max(active, 0), count - 1)
        let low = max(0, cursor - 80)
        let high = min(count, low + 240, cursor + 160)
        let adjustedLow = max(0, high - 240)
        return Array(adjustedLow..<high)
    }

    private func accessibilityProgress(count: Int) -> String {
        guard count > 0 else { return "empty" }
        return "\(min(activeIndex + 1, count)) of \(count)"
    }
}

// MARK: - View Identity

extension LessonTextView: Equatable {
    // Manual implementation: the @Environment members must not participate.
    // Lets SwiftUI skip this whole subtree on timer ticks that only change
    // the toolbar metrics, via `.equatable()` at the call site.
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.text == rhs.text
            && lhs.activeIndex == rhs.activeIndex
            && lhs.states == rhs.states
    }
}

// MARK: - Private

private struct CharacterCell: View, Equatable {
    @Environment(\.colorScheme) private var scheme
    var char: Character
    var state: CharState?
    var isActive: Bool
    var width: CGFloat

    static let activePadding: CGFloat = 7

    // Manual implementation: the @Environment member must not participate.
    // Unchanged cells then skip re-render on every keystroke (paired with
    // `.equatable()` above — only the two flipped cells rebuild).
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.char == rhs.char && lhs.state == rhs.state && lhs.isActive == rhs.isActive && lhs.width == rhs.width
    }

    var body: some View {
        // The active branch is a separate view, so it is created fresh on
        // each switch and its pop starts from the top. `.identity` keeps the
        // glide's transaction from cross-fading the two branches.
        if isActive {
            ActiveCell(glyph: glyph, width: width)
                .transition(.identity)
        } else {
            glyph
                .frame(width: width)
                .transition(.identity)
        }
    }

    private var glyph: some View {
        Text(displayed)
            .font(.system(size: LessonTextView.fontSize, weight: .medium, design: .monospaced))
            .foregroundStyle(color)
            .lineLimit(1)
            // Wider fallback glyphs overflow their cell instead of being
            // truncated or shifting the rest of the strip.
            .fixedSize()
    }

    private var displayed: String {
        if char == "\n" { return " " }
        if char == "\t" { return "⇥" }
        return String(char)
    }

    private var color: Color {
        switch state {
        case .correct: return Theme.ink(scheme)
        case .timeout: return Theme.muted(scheme)
        case .error: return Theme.error(scheme)
        case .errorTimeout: return Theme.errorTimeout(scheme)
        case nil: return Theme.pending(scheme)
        }
    }
}

/// Highlighted current character with the switch pop.
private struct ActiveCell<Glyph: View>: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var glyph: Glyph
    var width: CGFloat
    @State private var scale: CGFloat = 1.18

    var body: some View {
        glyph
            .frame(width: width)
            .padding(.horizontal, CharacterCell.activePadding)
            .padding(.vertical, 4)
            .background {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Theme.panel2(scheme))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Theme.brand(scheme), lineWidth: 1.5)
                    )
            }
            .scaleEffect(reduceMotion ? 1 : scale)
            .onAppear {
                // Quadratic ease-out, matching the Rust pop curve.
                withAnimation(.timingCurve(0.5, 1, 0.89, 1, duration: 0.14)) { scale = 1 }
            }
    }
}
