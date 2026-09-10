import SwiftUI

// MARK: - Completing First-Run Setup

/// Welcome cover shown until preferences are saved.
/// Mirrors `SetupPage` in `main.py`.
struct SetupView: View {
    @Environment(\.colorScheme) private var scheme
    @Bindable var state: AppState

    @State private var language: String = ""
    @State private var keyboard: String = ""
    @State private var typo: TypoMode = .typeRight
    @State private var goalWpm: String = "30"
    @State private var goalAccuracy: String = "95"
    @State private var autoStart = true
    @State private var backspace = true
    @State private var sound = false
    @State private var metronome = false
    @State private var invalid = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Image(nsImage: NSImage.bitAppIcon)
                    .resizable()
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.t("setup_welcome"))
                        .font(.system(size: 24, weight: .bold))
                    Text(state.t("setup_intro"))
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.muted(scheme))
                }
                Spacer()
            }
            .padding(24)
            Form {
                Section(state.t("setup_language_heading")) {
                    Picker(state.t("language"), selection: $language) {
                        ForEach(languageOptions, id: \.code) { option in
                            Text(option.label).tag(option.code)
                        }
                    }
                    .onChange(of: language) { _, next in
                        if let defaultKeyboard = state.languages[next]?.defaultKeyboard,
                            state.keyboardLayouts[defaultKeyboard] != nil
                        {
                            keyboard = defaultKeyboard
                        }
                    }
                    Picker(state.t("keyboard_layout"), selection: $keyboard) {
                        ForEach(keyboardOptions, id: \.code) { option in
                            Text(option.label).tag(option.code)
                        }
                    }
                }
                Section(state.t("setup_preferences_heading")) {
                    Picker(state.t("typo_behavior"), selection: $typo) {
                        Text(state.t("typo_right")).tag(TypoMode.typeRight)
                        Text(state.t("typo_backspace")).tag(TypoMode.backspace)
                        Text(state.t("typo_continue")).tag(TypoMode.cont)
                    }
                    HStack {
                        TextField(state.t("goal_speed"), text: $goalWpm)
                        TextField(state.t("goal_accuracy"), text: $goalAccuracy)
                    }
                    Toggle(state.t("auto_start"), isOn: $autoStart)
                    Toggle(state.t("allow_backspace"), isOn: $backspace)
                    Toggle(state.t("sound_feedback"), isOn: $sound)
                    Toggle(state.t("metronome"), isOn: $metronome)
                }
            }
            .formStyle(.grouped)
            HStack {
                Text(state.t("setup_change_later"))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted(scheme))
                Spacer()
                Button(action: finish) {
                    Label(state.t("finish_setup"), systemImage: "checkmark")
                }
                .buttonStyle(.appPrimary)
            }
            .padding(20)
        }
        .frame(width: 640, height: 640)
        .background(Theme.background(scheme))
        .onAppear(perform: load)
        .alert(state.t("invalid_options_title"), isPresented: $invalid) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(state.t("invalid_options_body"))
        }
    }

    // MARK: - Private

    private struct NamedOption {
        var code: String
        var label: String
    }

    private var languageOptions: [NamedOption] {
        state.languages.map { code, pack in
            NamedOption(code: code, label: pack.name.isEmpty ? code : "\(pack.name) (\(code))")
        }.sorted { $0.label < $1.label }
    }

    private var keyboardOptions: [NamedOption] {
        state.keyboardLayouts.map { code, layout in
            NamedOption(code: code, label: layout.name.isEmpty ? code : "\(layout.name) (\(code))")
        }.sorted { $0.label < $1.label }
    }

    private func load() {
        language = state.settings.language
        keyboard = state.settings.keyboardLayout
        typo = state.settings.typoMode
        goalWpm = String(state.settings.goalWpm)
        goalAccuracy = String(state.settings.goalAccuracy)
        autoStart = state.settings.autoStart
        backspace = state.settings.backspace
        sound = state.settings.sound
        metronome = state.settings.metronome
    }

    private func finish() {
        guard let wpm = Double(goalWpm), wpm >= 1,
            let accuracy = Double(goalAccuracy), accuracy >= 0, accuracy <= 100
        else {
            invalid = true
            return
        }
        state.settings.setupComplete = true
        state.settings.language = language
        state.settings.keyboardLayout = keyboard
        state.settings.typoMode = typo
        state.settings.goalWpm = wpm
        state.settings.goalAccuracy = accuracy
        state.settings.autoStart = autoStart
        state.settings.backspace = backspace
        state.settings.sound = sound
        state.settings.metronome = metronome
        state.saveSettings()
        state.loadResources()
        state.reloadCourses(select: state.selectedLesson)
        state.showingSetup = false
    }
}
