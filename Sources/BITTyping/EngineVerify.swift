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

        let state = AppState(autoRefreshRepos: false)
        let originalSettings = state.settings
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
            AppSupport.writeJSON(originalSettings, to: AppSupport.settingsFile)
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
        check("default pack seeded", !CourseRepos.collectAvailable(urls: [CourseRepos.defaultURL], layout: "HU-qwertz", custom: []).filter { !$0.repoName.isEmpty }.isEmpty)
        check("other layouts fall back to all pack lessons", !CourseRepos.collectAvailable(urls: [CourseRepos.defaultURL], layout: "US-qwerty", custom: []).filter { !$0.repoName.isEmpty }.isEmpty)
        check("default pack always configured", state.courseRepos.contains(where: CourseRepos.isDefault))
        resetGuards(state)

        // Finishing early saves an unfinished row; continuing it resumes at
        // the same character and finishing updates that same row.
        state.settings.typoMode = .typeRight
        state.settings.autoStart = true
        state.continuingFromID = nil
        state.session = Session(lesson: "early", text: "abcd", characters: Array("abcd"))
        state.startSession()
        state.handle(.character("a"))
        state.handle(.character("b"))
        state.finishEarly()
        let early = state.history.last
        check("early finish records row", state.history.count == historyCount + 2)
        check("early row is unfinished", early?.unfinished == true && early?.characters == 2,
              detail: "unfinished=\(String(describing: early?.unfinished)) chars=\(String(describing: early?.characters))")
        resetGuards(state)
        if let early {
            state.continueAttempt(early.id)
            check("continue restores position", state.session.index == 2, detail: "index=\(state.session.index)")
            check("continue waits for first key", !state.session.running && state.continuingFromID == early.id)
            check("continue keeps elapsed time", state.session.elapsed() >= early.duration)
            check("continue restores counters", state.session.correctKeys == 2 && state.session.typedKeys == 2)
            state.handle(.character("c"))
            check("typing resumes continuation", state.session.running && state.session.index == 3)
            state.handle(.character("d"))
            let finished = state.history.last
            check("continuation updates row in place", state.history.count == historyCount + 2 && finished?.id == early.id)
            check("continued row is finished", finished?.unfinished == false && finished?.characters == 4)
            check("continued row keeps start time", finished?.startedAt == early.startedAt)
        }
        resetGuards(state)

        // Saving options must not reset the lesson in progress.
        state.session = Session(lesson: "opt", text: "abc", characters: Array("abc"))
        state.startSession()
        state.handle(.character("a"))
        var updated = state.settings
        updated.goalWpm = state.settings.goalWpm + 1
        updated.typoMode = .cont
        state.applySettings(updated)
        check("options keep lesson", state.session.index == 1 && state.session.running && state.session.lesson == "opt")
        state.pauseForModal()
        check("modal pauses lesson", state.session.paused)

        // Course pack details: map form, list form, slugs, default URL.
        let mapForm = try? CourseRepos.parseDetails(Data(#"{"name":"N","creator":"C","courses":{"HU-qwertz":["HU-qwertz/a.txt"],"US-qwerty":["US-qwerty/b.txt"]}}"#.utf8))
        check("details map form", mapForm?.courses.count == 2 && mapForm?.name == "N")
        let listForm = try? CourseRepos.parseDetails(Data(#"{"name":"N","courses":[{"layout":"HU-qwertz","path":"HU-qwertz/a.txt","title":"Intro"}]}"#.utf8))
        check("details list form", listForm?.courses.first?.title == "Intro")
        check("slug from url", CourseRepos.slug(for: "https://github.com/x/y.git/") == "y")
        check("default url variants", CourseRepos.isDefault("https://github.com/bitiskola/bit-typing-main.git"))
        func course(_ id: String, _ title: String, _ pack: String) -> AvailableCourse {
            AvailableCourse(id: id, title: title, repoName: pack, layout: "HU-qwertz", url: URL(fileURLWithPath: "/"), courseFile: id, custom: false)
        }
        let packs = [course("a", "01", "P"), course("b", "02", "P"), course("c", "02", "Q")]
        check("next course stays in pack", CourseRepos.nextCourse(in: packs, after: "a")?.id == "b")
        check("last course has no next", CourseRepos.nextCourse(in: packs, after: "b") == nil)

        // History written by older versions (no new keys) still loads.
        let legacy = try? JSONDecoder().decode([Attempt].self, from: Data(#"[{"lesson":"x","wpm":10,"started_at":"s"}]"#.utf8))
        check("legacy history decodes", legacy?.first?.lesson == "x" && legacy?.first?.unfinished == false)
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
