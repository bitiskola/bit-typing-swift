import SwiftUI

// MARK: - Changing Options

/// Settings sheet. Edits a draft and applies it on save, mirroring
/// `OptionsPage` in `main.py`.
struct OptionsView: View {
    @Environment(\.colorScheme) private var scheme
    @Bindable var state: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var language: String = ""
    @State private var keyboard: String = ""
    @State private var typo: TypoMode = .typeRight
    @State private var goalWpm: String = ""
    @State private var goalAccuracy: String = ""
    @State private var timeout: String = ""
    @State private var timedMinutes: String = ""
    @State private var autoStart = true
    @State private var backspace = true
    @State private var metronome = false
    @State private var sound = false
    @State private var invalid = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(state.t("options"))
                    .font(.system(size: 22, weight: .bold))
                Spacer()
                Button(state.t("cancel")) { dismiss() }
                    .buttonStyle(.appSecondary)
            }
            .padding(20)
            Form {
                Section(state.t("lesson_behavior")) {
                    Picker(state.t("language"), selection: $language) {
                        ForEach(state.languages.keys.sorted(), id: \.self) { code in
                            Text(code).tag(code)
                        }
                    }
                    Picker(state.t("keyboard_layout"), selection: $keyboard) {
                        ForEach(state.keyboardLayouts.keys.sorted(), id: \.self) { code in
                            Text(code).tag(code)
                        }
                    }
                    Picker(state.t("typo_behavior"), selection: $typo) {
                        Text(state.t("typo_right")).tag(TypoMode.typeRight)
                        Text(state.t("typo_backspace")).tag(TypoMode.backspace)
                        Text(state.t("typo_continue")).tag(TypoMode.cont)
                    }
                    TextField(state.t("goal_speed"), text: $goalWpm)
                    TextField(state.t("goal_accuracy"), text: $goalAccuracy)
                    TextField(state.t("slow_threshold"), text: $timeout)
                    TextField(state.t("timed_lesson"), text: $timedMinutes)
                    Toggle(state.t("auto_start"), isOn: $autoStart)
                    Toggle(state.t("allow_backspace"), isOn: $backspace)
                    Toggle(state.t("metronome"), isOn: $metronome)
                    Toggle(state.t("sound_feedback"), isOn: $sound)
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button { dismiss() } label: {
                    Label(state.t("cancel"), systemImage: "xmark")
                }
                .buttonStyle(.appSecondary)
                Button(action: save) {
                    Label(state.t("save_options"), systemImage: "checkmark")
                }
                .buttonStyle(.appPrimary)
            }
            .padding(16)
        }
        .frame(width: 560, height: 620)
        .background(Theme.background(scheme))
        .onAppear(perform: load)
        .alert(state.t("invalid_options_title"), isPresented: $invalid) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(state.t("invalid_options_body"))
        }
    }

    // MARK: - Private

    private func load() {
        language = state.settings.language
        keyboard = state.settings.keyboardLayout
        typo = state.settings.typoMode
        goalWpm = String(state.settings.goalWpm)
        goalAccuracy = String(state.settings.goalAccuracy)
        timeout = String(state.settings.timeoutSeconds)
        timedMinutes = String(state.settings.timedMinutes)
        autoStart = state.settings.autoStart
        backspace = state.settings.backspace
        metronome = state.settings.metronome
        sound = state.settings.sound
    }

    private func save() {
        guard let wpm = Double(goalWpm), wpm >= 1,
            let accuracy = Double(goalAccuracy), accuracy >= 0, accuracy <= 100,
            let slow = Double(timeout), slow >= 0.1,
            let timed = Double(timedMinutes), timed >= 0
        else {
            invalid = true
            return
        }
        let oldLanguage = state.settings.language
        state.settings.language = language
        state.settings.keyboardLayout = keyboard
        state.settings.typoMode = typo
        state.settings.goalWpm = wpm
        state.settings.goalAccuracy = accuracy
        state.settings.timeoutSeconds = slow
        state.settings.timedMinutes = timed
        state.settings.autoStart = autoStart
        state.settings.backspace = backspace
        state.settings.metronome = metronome
        state.settings.sound = sound
        if language != oldLanguage,
            let defaultKeyboard = state.languages[language]?.defaultKeyboard,
            state.keyboardLayouts[defaultKeyboard] != nil
        {
            state.settings.keyboardLayout = defaultKeyboard
        }
        state.saveSettings()
        state.loadResources()
        state.reloadCourses(select: state.selectedLesson)
        dismiss()
    }
}
