import SwiftUI

// MARK: - Showing Lesson Text

/// Scrolling lesson viewport. Completed text fills left, future text fills
/// right, and the active character stays centered with a blue-outlined
/// highlight — the SwiftUI counterpart of `render_text()` in `main.py`.
struct LessonTextView: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var text: String
    var states: [Int: CharState]
    var activeIndex: Int

    var body: some View {
        // Convert once: `characters` used to be a computed property, so every
        // `characters[offset]` inside the cell loop reconverted the whole
        // string (~240 full conversions per keystroke on long lessons).
        let chars = Array(text)
        let offsets = Self.visibleOffsets(count: chars.count, active: activeIndex)
        return GeometryReader { proxy in
            ScrollViewReader { scroll in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        // Leading spacer keeps the first char centered.
                        Color.clear.frame(width: max(0, proxy.size.width * 0.48 - 40))
                        HStack(spacing: 0) {
                            // Window the cells: a 2394-char lesson rendered as
                            // 2394 Text views blocks the main thread (beachball
                            // on launch, Start unclickable). Render ~240 cells
                            // around the cursor like render_text() does.
                            ForEach(offsets, id: \.self) { offset in
                                CharacterCell(
                                    char: chars[offset],
                                    state: states[offset],
                                    isActive: offset == activeIndex && activeIndex < chars.count
                                )
                                .equatable()
                                .id(offset)
                            }
                        }
                        Color.clear.frame(width: max(0, proxy.size.width * 0.5))
                    }
                    .frame(minHeight: proxy.size.height)
                }
                .onChange(of: activeIndex) { old, next in
                    let target = min(next, max(0, chars.count - 1))
                    // Single-step typing advances need no animation: a fresh
                    // 0.12s easeOut on every keystroke piles overlapping
                    // animations onto weak GPUs so the text trails the keys.
                    // Animate only real jumps (restart, lesson switch).
                    if reduceMotion || abs(next - old) <= 8 {
                        scroll.scrollTo(target, anchor: .center)
                    } else {
                        withAnimation(.easeOut(duration: 0.12)) {
                            scroll.scrollTo(target, anchor: .center)
                        }
                    }
                }
                .onAppear {
                    scroll.scrollTo(min(activeIndex, max(0, chars.count - 1)), anchor: .center)
                }
            }
        }
        // VoiceOver reads the lesson as one adjustable value instead of
        // reconstructing meaning from individual cells.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Lesson text"))
        .accessibilityValue(Text(accessibilityProgress(count: chars.count)))
    }

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

    // Manual implementation: the @Environment member must not participate.
    // Unchanged cells then skip re-render on every keystroke (paired with
    // `.equatable()` above — only the two flipped cells rebuild).
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.char == rhs.char && lhs.state == rhs.state && lhs.isActive == rhs.isActive
    }

    var body: some View {
        Text(displayed)
            .font(.system(size: 44, weight: .medium, design: .monospaced))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background {
                if isActive {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Theme.panel2(scheme))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Theme.brand(scheme), lineWidth: 1.5)
                        )
                }
            }
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
