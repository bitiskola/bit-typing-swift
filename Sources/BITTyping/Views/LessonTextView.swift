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
        GeometryReader { proxy in
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
                            ForEach(visibleOffsets, id: \.self) { offset in
                                CharacterCell(
                                    char: characters[offset],
                                    state: states[offset],
                                    isActive: offset == activeIndex && activeIndex < characters.count
                                )
                                .id(offset)
                            }
                        }
                        Color.clear.frame(width: max(0, proxy.size.width * 0.5))
                    }
                    .frame(minHeight: proxy.size.height)
                }
                .onChange(of: activeIndex) { _, next in
                    let target = min(next, max(0, characters.count - 1))
                    if reduceMotion {
                        scroll.scrollTo(target, anchor: .center)
                    } else {
                        withAnimation(.easeOut(duration: 0.12)) {
                            scroll.scrollTo(target, anchor: .center)
                        }
                    }
                }
                .onAppear {
                    scroll.scrollTo(min(activeIndex, max(0, characters.count - 1)), anchor: .center)
                }
            }
        }
        // VoiceOver reads the lesson as one adjustable value instead of
        // reconstructing meaning from individual cells.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Lesson text"))
        .accessibilityValue(Text(accessibilityProgress))
    }

    private var characters: [Character] {
        Array(text)
    }

    /// Visible window around the cursor. Keeps ~80 finished chars on the
    /// left and ~160 upcoming chars on the right so long lessons stay at
    /// a flat view count instead of growing with lesson length.
    private var visibleOffsets: [Int] {
        let count = characters.count
        guard count > 0 else { return [] }
        let low = max(0, min(activeIndex, count - 1) - 80)
        let high = min(count, low + 240, min(activeIndex, count - 1) + 160)
        let adjustedLow = max(0, high - 240)
        return Array(adjustedLow..<high)
    }

    private var accessibilityProgress: String {
        guard !characters.isEmpty else { return "empty" }
        return "\(min(activeIndex + 1, characters.count)) of \(characters.count)"
    }
}

// MARK: - Private

private struct CharacterCell: View {
    @Environment(\.colorScheme) private var scheme
    var char: Character
    var state: CharState?
    var isActive: Bool

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
