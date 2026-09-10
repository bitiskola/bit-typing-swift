import Foundation

// MARK: - Verifying the Typing Engine

/// Headless self-test (`swift run BITTyping --verify-engine`) for machines
/// without Xcode's testing libraries. Exercises the real `AppState`
/// engine and restores `history.json` afterwards.
@MainActor
enum EngineVerify {
    static func run() -> (passed: Int, failed: [(String, String)]) {
        var passed = 0
        var failed: [(String, String)] = []
        func check(_ name: String, _ condition: @autoclosure () -> Bool, detail: String = "") {
            if condition() {
                passed += 1
            } else {
                failed.append((name, detail))
            }
        }

        let state = AppState()
        state.settings.sound = false
        state.settings.metronome = false
        // Bypass first-run and modal guards so keystrokes reach the engine.
        state.showingSetup = false
        state.showingOptions = false
        state.showingAbout = false
        state.showingWellDone = false
        state.resultsAttempt = nil
        state.selectedTab = .lesson
        let historyCount = state.history.count
        defer {
            state.history = Array(state.history.prefix(historyCount))
            AppSupport.writeJSON(state.history, to: AppSupport.historyFile)
        }

        // Correct characters advance and finish the lesson.
        state.settings.typoMode = .typeRight
        state.session = Session(lesson: "test", text: "ab", characters: Array("ab"))
        state.startSession()
        state.handle(.character("a"))
        check("correct advances", state.session.index == 1, detail: "index=\(state.session.index)")
        state.handle(.character("b"))
        check("finishing records history", state.history.count == historyCount + 1)
        check("perfect accuracy", state.history.last?.accuracy == 100)
        resetGuards(state)

        // Type-right mode: errors stay on the character.
        state.settings.typoMode = .typeRight
        state.session = Session(lesson: "test", text: "ab", characters: Array("ab"))
        state.startSession()
        state.handle(.character("x"))
        check("error holds position", state.session.index == 0)
        check("error counted", state.session.errors == 1)
        state.handle(.character("a"))
        check("retry advances", state.session.index == 1)
        resetGuards(state)

        // Backspace mode: must clear the error first.
        state.settings.typoMode = .backspace
        state.session = Session(lesson: "test", text: "ab", characters: Array("ab"))
        state.startSession()
        state.handle(.character("x"))
        check("backspace mode blocks", state.session.pendingWrong)
        state.handle(.character("a"))
        check("blocked char ignored", state.session.index == 0)
        state.handle(.backspace)
        check("backspace clears", !state.session.pendingWrong)
        state.handle(.character("a"))
        check("corrected char advances", state.session.index == 1)
        resetGuards(state)

        // Continue mode: skips ahead after errors.
        state.settings.typoMode = .cont
        state.session = Session(lesson: "test", text: "ab", characters: Array("ab"))
        state.startSession()
        state.handle(.character("x"))
        check("continue skips", state.session.index == 1)

        // Backspace key on a clean position steps back and marks fixed.
        state.settings.typoMode = .typeRight
        state.session = Session(lesson: "test", text: "ab", characters: Array("ab"))
        state.startSession()
        state.handle(.character("a"))
        state.handle(.backspace)
        check("backspace steps back", state.session.index == 0)
        check("stepped char marked fixed", state.session.fixedIndices.contains(0))

        // Scoring blends accuracy, speed, and slowdown.
        let perfect = Attempt(wpm: state.settings.goalWpm, accuracy: 100, slowdown: 0)
        check("perfect score is 100", abs(state.overallScore(for: perfect) - 100) < 0.001)
        // Lesson text decoding handles BOM-less and legacy encodings.
        check("courses seeded", !state.courseNames.isEmpty)
        check("languages loaded", state.languages["EN-us"] != nil)
        check("layouts loaded", state.keyboardLayouts["US-qwerty"] != nil)
        check("fallback string", !state.t("start_lesson").isEmpty)

        return (passed, failed)
    }

    // MARK: - Private

    /// A finished lesson raises the well-done overlay, which correctly
    /// blocks further keystrokes. Clear it between scenarios.
    private static func resetGuards(_ state: AppState) {
        state.showingWellDone = false
        state.resultsAttempt = nil
    }
}
