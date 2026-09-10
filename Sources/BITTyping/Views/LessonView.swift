import AppKit
import SwiftUI

// MARK: - Practicing Lessons

/// Main practice page: scrolling text, tip pill, virtual keyboard, and
/// progress footer — all open, no cards or hairlines. Controls live in the
/// native window toolbar (`ToolbarItem` + `visibilityPriority`), and actions
/// use the system Liquid Glass button styles.
struct LessonView: View {
    @Environment(\.colorScheme) private var scheme
    @Bindable var state: AppState

    var body: some View {
            VStack(spacing: 24) {
                lessonText
                keyboardBlock
                footer
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .background(
                KeyCaptureView(onEvent: { state.handle($0) }, onRestart: { state.restartLesson() })
                    .frame(width: 0, height: 0)
            )
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    lessonPicker
                }

                ToolbarItem(placement: .primaryAction) {
                    startButton
                }

                ToolbarItem {
                    MetricView(title: state.t("time"), value: formattedTime)
                        .padding(.horizontal, 8)
                }

                ToolbarItem {
                    MetricView(title: state.t("accuracy"), value: "\(Int(state.liveAccuracy.rounded()))%")
                        .padding(.horizontal, 8)
                }

                ToolbarItem {
                    MetricView(title: state.t("speed"), value: formattedSpeed)
                        .padding(.horizontal, 8)
                }
            }
            // SwiftUI has no `visibilityPriority` modifier (that snippet
            // doesn't compile) — the same-named knob lives on the native
            // `NSToolbarItem`, which is what these `ToolbarItem`s become.
            // This pushes declaration order into native priorities so a
            // narrow window collapses speed/accuracy/time first and keeps
            // Start/Pause: picker .high, start .user (never collapses),
            // metrics .standard/.low/.low.
            .background(
                ToolbarPrioritySetter(priorities: [.high, .user, .standard, .low, .low])
                    .frame(width: 0, height: 0)
            )
            .navigationTitle(state.selectedLesson.isEmpty ? state.t("current_lesson") : state.selectedLesson)
    }

    // MARK: - Private

    /// Lesson picker lives in the toolbar; empty state shows inline text.
    private var lessonPicker: some View {
        Group {
            if state.courseNames.isEmpty {
                Text(state.t("no_lessons"))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted(scheme))
            } else {
                Picker("", selection: $state.selectedLesson) {
                    ForEach(state.courseNames, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .frame(minWidth: 180, maxWidth: 260)
                .onChange(of: state.selectedLesson) { _, _ in state.prepareLesson() }
            }
        }
    }

    private var startButton: some View {
        Group {
            if #available(macOS 26, *) {
                Button(action: state.toggleStart) {
                    Label(state.t(state.startButtonKey), systemImage: startIcon)
                }
                .buttonStyle(.glassProminent)
                .tint(Theme.brand(scheme))
                .disabled(state.currentURL() == nil)
            } else {
                Button(action: state.toggleStart) {
                    Label(state.t(state.startButtonKey), systemImage: startIcon)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.brand(scheme))
                .disabled(state.currentURL() == nil)
            }
        }
    }

    /// Play while idle/paused, pause while running.
    private var startIcon: String {
        state.session.running && !state.session.paused ? "pause.fill" : "play.fill"
    }

    /// Open text area — no card, no border. Absorbs extra space in
    /// fullscreen; minimum keeps the default window layout stable.
    private var lessonText: some View {
        LessonTextView(text: state.session.text, states: state.session.states, activeIndex: state.session.index)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .frame(minHeight: 170, maxHeight: .infinity)
            .layoutPriority(1)
    }

    /// Open keyboard — no card, no hairlines, generous breathing room.
    private var keyboardBlock: some View {
        VStack(spacing: 12) {
            KeyboardView(layout: state.keyboardLayout, activeChar: activeCharacter)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            fingerLegend
        }
        .frame(maxWidth: .infinity)
        .frame(height: 300)
    }

    /// Which tint belongs to which finger.
    private var fingerLegend: some View {
        HStack(spacing: 14) {
            ForEach(fingerLegendItems, id: \.0) { zone, label in
                HStack(spacing: 5) {
                    Circle()
                        .fill(fingerTint(zone, scheme: scheme))
                        .frame(width: 10, height: 10)
                    Text(label)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.muted(scheme))
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(state.t("keyboard_layout")))
    }

    private var fingerLegendItems: [(FingerZone, String)] {
        [
            (.pinky, state.t("finger_pinky")),
            (.ring, state.t("finger_ring")),
            (.middle, state.t("finger_middle")),
            (.index, state.t("finger_index")),
        ]
    }

    private var footer: some View {
        HStack {
            Spacer()
            Text("\(state.session.index) / \(state.session.characters.count)")
                .font(.system(size: 13))
                .foregroundStyle(Theme.muted(scheme))
            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .tint(Theme.brand(scheme))
                .frame(width: 230)
        }
        .padding(.horizontal, 8)
        .frame(height: 30)
    }

    private var formattedTime: String {
        let total = Int(state.liveElapsed)
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }

    private var formattedSpeed: String {
        let value = Int((state.liveWpm * state.speedUnit.factor).rounded())
        return "\(value) \(state.t(state.speedUnit.unitKey))"
    }

    private var progress: Double {
        guard !state.session.characters.isEmpty else { return 0 }
        return Double(state.session.index) / Double(state.session.characters.count)
    }

    private var activeCharacter: String {
        guard state.session.index < state.session.characters.count else { return "" }
        return String(state.session.characters[state.session.index])
    }
}
