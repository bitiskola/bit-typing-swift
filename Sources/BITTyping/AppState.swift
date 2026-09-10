import Foundation
import Observation

// MARK: - Handling Key Input

/// Normalized key events from the capture view.
enum KeyInput: Sendable {
    case character(String)
    case backspace
    case escape
    case systemKey(String)
}

// MARK: - Driving the Typing Tutor

/// Central store: lesson engine, persistence, and navigation state.
/// Ports `TypingApp` from `main.py` to SwiftUI idioms.
@Observable @MainActor
final class AppState {

    // MARK: - Reading App State

    var settings = AppSettings()
    var history: [Attempt] = []
    var customCourses: Set<String> = []
    var languages: [String: LanguagePack] = [:]
    var keyboardLayouts: [String: KeyboardLayout] = [:]

    var courseNames: [String] = []
    var selectedLesson: String = ""
    var lastLessonName: String = ""
    var session = Session()

    var liveWpm: Double = 0
    var liveAccuracy: Double = 100
    var liveElapsed: TimeInterval = 0
    var tipKey: String = "initial_tip"
    var tipArgs: [String: String] = [:]
    var startButtonKey = "start_lesson"

    var selectedTab: AppTab = .lesson
    var showingOptions = false
    var showingAbout = false
    var showingSetup = false
    var showingWellDone = false
    var resultsAttempt: Attempt? = nil
    var selectedHistoryID: UUID? = nil

    var editorName: String = ""
    var editorText: String = ""

    var speedUnit: SpeedUnit = .wpm

    var loadError: String? = nil
    var noticeTitleKey: String? = nil
    var noticeMessage: String? = nil

    // MARK: - Internal

    private let sound = SoundService()
    private var timer: Timer? = nil
    private var lastMetronomeSecond: Int = -1
    private var wellDoneTask: Task<Void, Never>? = nil

    init() {
        AppSupport.ensureSeeded()
        settings = AppSupport.readJSON(AppSupport.settingsFile, as: AppSettings.self, default: AppSettings())
        history = AppSupport.readJSON(AppSupport.historyFile, as: [Attempt].self, default: [])
        let savedCustom = AppSupport.readJSON(AppSupport.customCoursesFile, as: [String].self, default: [])
        customCourses = Set(savedCustom)
        if let raw = UserDefaults.standard.string(forKey: "bittyping.speedUnit"),
            let unit = SpeedUnit(rawValue: raw)
        {
            speedUnit = unit
        }
        loadResources()
        reloadCourses(select: nil)
        showingSetup = !settings.setupComplete
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    // MARK: - Localizing Strings

    /// Localized string with English fallback, mirroring `TypingApp.t()`.
    func t(_ key: String) -> String {
        if let hit = languages[settings.language]?.strings[key] { return hit }
        if let hit = languages["EN-us"]?.strings[key] { return hit }
        return key.replacingOccurrences(of: "_", with: " ").capitalized
    }

    func t(_ key: String, args: [String: String]) -> String {
        var out = t(key)
        for (name, value) in args {
            // Packs use both `{name}` and Python-style `{name:format}`
            // (e.g. `{best:.1f}` in `history_summary`); values arrive
            // pre-formatted, so the spec is matched but ignored.
            if let regex = try? NSRegularExpression(
                pattern: "\\{\(NSRegularExpression.escapedPattern(for: name))(?::[^}]*)?\\}"
            ) {
                out = regex.stringByReplacingMatches(
                    in: out,
                    range: NSRange(out.startIndex..., in: out),
                    withTemplate: NSRegularExpression.escapedTemplate(for: value)
                )
            }
        }
        return out
    }

    var keyboardLayout: KeyboardLayout {
        keyboardLayouts[settings.keyboardLayout]
            ?? keyboardLayouts.values.first
            ?? KeyboardLayout()
    }

    var typoLabel: String {
        switch settings.typoMode {
        case .typeRight: return t("typo_right")
        case .backspace: return t("typo_backspace")
        case .cont: return t("typo_continue")
        }
    }

    // MARK: - Loading Resources

    func loadResources() {
        var langs: [String: LanguagePack] = [:]
        if let files = try? FileManager.default.contentsOfDirectory(at: AppSupport.languages, includingPropertiesForKeys: nil) {
            for file in files where file.pathExtension == "json" {
                langs[file.deletingPathExtension().lastPathComponent] = AppSupport.readJSON(file, as: LanguagePack.self, default: LanguagePack())
            }
        }
        var layouts: [String: KeyboardLayout] = [:]
        if let files = try? FileManager.default.contentsOfDirectory(at: AppSupport.keyboards, includingPropertiesForKeys: nil) {
            for file in files where file.pathExtension == "json" {
                layouts[file.deletingPathExtension().lastPathComponent] = AppSupport.readJSON(file, as: KeyboardLayout.self, default: KeyboardLayout())
            }
        }
        languages = langs
        keyboardLayouts = layouts
        if languages[settings.language] == nil {
            settings.language = languages["EN-us"] != nil ? "EN-us" : (languages.keys.sorted().first ?? "")
        }
        if keyboardLayouts[settings.keyboardLayout] == nil {
            settings.keyboardLayout = languages[settings.language]?.defaultKeyboard
                ?? keyboardLayouts.keys.sorted().first ?? ""
        }
    }

    func saveSettings() {
        AppSupport.writeJSON(settings, to: AppSupport.settingsFile)
    }

    func setSpeedUnit(_ unit: SpeedUnit) {
        speedUnit = unit
        UserDefaults.standard.set(unit.rawValue, forKey: "bittyping.speedUnit")
    }

    // MARK: - Managing Lessons

    func reloadCourses(select: String?) {
        let files = (try? FileManager.default.contentsOfDirectory(at: AppSupport.courses, includingPropertiesForKeys: nil)) ?? []
        courseNames = files
            .filter { $0.pathExtension == "txt" }
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted { $0.caseInsensitiveCompare($1) == .orderedAscending }
        if let select, courseNames.contains(select) {
            selectedLesson = select
        } else if !courseNames.contains(selectedLesson) {
            selectedLesson = courseNames.first ?? ""
        }
        prepareLesson()
    }

    func currentURL() -> URL? {
        guard !selectedLesson.isEmpty else { return nil }
        let url = AppSupport.courses.appendingPathComponent(selectedLesson + ".txt")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Reset state for the selected lesson without starting the clock.
    func prepareLesson() {
        if let url = currentURL() {
            do {
                // Editors commonly leave one terminal newline; it must not
                // require an invisible final Enter press to finish.
                let raw = try CourseText.read(url)
                let text = raw.replacingOccurrences(of: "[\\r\\n]+$", with: "", options: .regularExpression)
                session = Session(lesson: selectedLesson, text: text, characters: Array(text))
                lastLessonName = selectedLesson
            } catch {
                loadError = t("lesson_load_failed_body", args: ["name": url.lastPathComponent, "error": error.localizedDescription])
                session = Session()
            }
        } else {
            session = Session(lesson: "", text: t("initial_tip"), characters: [])
        }
        startButtonKey = "start_lesson"
        tipKey = "ready_tip"
        updateLive()
    }

    func toggleStart() {
        guard currentURL() != nil else { return }
        if !session.running {
            startSession()
        } else if session.paused {
            session.pausedTotal += Date().timeIntervalSince(session.pausedAt ?? Date())
            session.paused = false
            startButtonKey = "pause"
            tipKey = "lesson_resumed"
        } else {
            session.paused = true
            session.pausedAt = Date()
            startButtonKey = "resume"
            tipKey = "paused_tip"
        }
    }

    func restartLesson() {
        prepareLesson()
    }

    func startSession() {
        let now = Date()
        session.startedAt = now
        session.lastKeyAt = now
        session.startedWall = isoNow()
        session.running = true
        session.paused = false
        startButtonKey = "pause"
        tipKey = "typing_tip"
    }

    // MARK: - Handling Keystrokes

    /// Returns true when the event was consumed.
    @discardableResult
    func handle(_ input: KeyInput, allowAutoStart: Bool = true) -> Bool {
        guard resultsAttempt == nil, !showingWellDone, !showingOptions, !showingAbout, !showingSetup,
            selectedTab == .lesson
        else { return false }
        switch input {
        case .escape:
            if session.running { toggleStart() }
            return true
        case .systemKey(let name):
            guard session.running, !session.paused, session.index < session.characters.count else { return true }
            recordSystem(name)
            return true
        case .backspace:
            guard session.running else { return false }
            guard !session.paused, session.index <= session.characters.count else { return true }
            handleBackspace()
            return true
        case .character(let actual):
            guard actual.count == 1 else { return true }
            if !session.running {
                guard allowAutoStart,
                    settings.autoStart,
                    currentURL() != nil,
                    session.index < session.characters.count,
                    actual == "\t" || actual.first?.isNewline == true || actual.first?.isPrintableASCIIOrBeyond == true
                else { return false }
                startSession()
            }
            guard !session.paused, session.index < session.characters.count else { return true }
            handleCharacter(actual)
            return true
        }
    }

    private func recordSystem(_ key: String) {
        let now = Date()
        let delay = now.timeIntervalSince(session.lastKeyAt ?? now)
        session.lastKeyAt = now
        session.strokes.append(Stroke(expected: "", actual: key, timestamp: now.timeIntervalSince1970, delay: delay, correct: true, timedOut: false, index: session.index, systemKey: true))
    }

    private func handleBackspace() {
        guard settings.backspace else {
            tipKey = "backspace_disabled"
            return
        }
        let now = Date()
        let delay = now.timeIntervalSince(session.lastKeyAt ?? now)
        session.lastKeyAt = now
        session.backspaces += 1
        session.strokes.append(Stroke(expected: "", actual: "Backspace", timestamp: now.timeIntervalSince1970, delay: delay, correct: true, timedOut: false, index: session.index, systemKey: true))
        let currentIsError = session.states[session.index] == .error || session.states[session.index] == .errorTimeout
        if session.pendingWrong || currentIsError {
            session.pendingWrong = false
            session.states.removeValue(forKey: session.index)
            tipKey = "type_correct"
        } else if session.index > 0 {
            session.index -= 1
            session.fixedIndices.insert(session.index)
            session.states.removeValue(forKey: session.index)
            session.pendingWrong = false
        }
        playKey(correct: true)
    }

    private func handleCharacter(_ actual: String) {
        if settings.typoMode == .backspace, session.pendingWrong {
            tipKey = "press_backspace"
            playKey(correct: false)
            return
        }
        let expected = String(session.characters[session.index])
        let now = Date()
        let delay = now.timeIntervalSince(session.lastKeyAt ?? now)
        session.lastKeyAt = now
        let timedOut = delay > settings.timeoutSeconds
        let correct = actual == expected
        session.typedKeys += 1
        if correct { session.correctKeys += 1 }
        session.strokes.append(Stroke(expected: expected, actual: actual, timestamp: now.timeIntervalSince1970, delay: delay, correct: correct, timedOut: timedOut, index: session.index))
        if timedOut { session.timeouts += 1 }
        if correct {
            session.states[session.index] = timedOut ? .timeout : .correct
            session.index += 1
            session.pendingWrong = false
        } else {
            session.errors += 1
            session.fixedIndices.insert(session.index)
            session.states[session.index] = timedOut ? .errorTimeout : .error
            switch settings.typoMode {
            case .cont:
                session.index += 1
            case .backspace:
                session.pendingWrong = true
            case .typeRight:
                break
            }
        }
        playKey(correct: correct)
        if session.index >= session.characters.count {
            finishSession()
        }
    }

    // MARK: - Updating Live Metrics

    func tick() {
        if session.running, !session.paused {
            updateLive()
            if settings.metronome, settings.sound {
                let second = Int(session.elapsed())
                if second != lastMetronomeSecond {
                    lastMetronomeSecond = second
                    sound.tick()
                }
            }
            let limit = settings.timedMinutes * 60
            if limit > 0, session.elapsed() >= limit {
                finishSession()
            }
        }
    }

    func updateLive() {
        let elapsed = session.elapsed()
        liveElapsed = elapsed
        liveWpm = elapsed > 0 ? Double(session.correctKeys) / 5 / (elapsed / 60) : 0
        liveAccuracy = session.typedKeys > 0 ? Double(session.correctKeys) / Double(session.typedKeys) * 100 : 100
    }

    // MARK: - Finishing Lessons

    func finishSession() {
        guard session.running else { return }
        session.running = false
        let duration = max(0.01, session.elapsed())
        let normal = session.strokes.filter { !$0.systemKey }
        let correct = normal.filter { $0.correct }.count
        let accuracy = normal.isEmpty ? 100 : Double(correct) / Double(normal.count) * 100
        let wpm = Double(correct) / 5 / (duration / 60)
        let slowdown = normal.isEmpty ? 0 : Double(session.timeouts) / Double(normal.count) * 100
        var resultStates: [String: CharState] = [:]
        for (index, state) in session.states { resultStates[String(index)] = state }
        // Characters fixed via Backspace count as errors in the report,
        // while the live lesson showed them as accepted.
        for index in session.fixedIndices {
            if resultStates[String(index)] == .timeout { resultStates[String(index)] = .errorTimeout }
            else { resultStates[String(index)] = .error }
        }
        let fixedWords = Set(session.fixedIndices.compactMap { Self.word(at: $0, in: session.text) }.filter { !$0.isEmpty }).count
        let fileName = currentURL()?.lastPathComponent ?? ""
        let attempt = Attempt(
            lesson: session.lesson,
            startedAt: session.startedWall,
            courseFile: fileName,
            customCourse: customCourses.contains(fileName),
            finishedAt: isoNow(),
            duration: duration,
            wpm: wpm,
            accuracy: accuracy,
            slowdown: slowdown,
            done: session.text.isEmpty ? 0 : Double(session.index) / Double(session.characters.count) * 100,
            words: session.text.prefix(sessionTextPrefixLength()).split(whereSeparator: \.isWhitespace).count,
            fixedWords: fixedWords,
            characters: session.index,
            fixedCharacters: session.fixedIndices.count,
            errors: session.errors,
            timeouts: session.timeouts,
            backspaces: session.backspaces,
            passed: wpm >= settings.goalWpm && accuracy >= settings.goalAccuracy,
            text: session.text,
            states: resultStates,
            strokes: session.strokes
        )
        history.append(attempt)
        AppSupport.writeJSON(history, to: AppSupport.historyFile)
        startButtonKey = "start_lesson"
        updateLive()
        showingWellDone = true
        wellDoneTask?.cancel()
        wellDoneTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self.showingWellDone = false
            self.resultsAttempt = attempt
        }
    }

    private func sessionTextPrefixLength() -> Int {
        session.text.prefix(session.index).count
    }

    // MARK: - Navigating Between Lessons

    /// Next numbered built-in lesson, or nil for custom/final lessons.
    func nextLessonURL(for attempt: Attempt) -> URL? {
        let files = (try? FileManager.default.contentsOfDirectory(at: AppSupport.courses, includingPropertiesForKeys: nil)) ?? []
        let byName = Dictionary(uniqueKeysWithValues: files.map { ($0.lastPathComponent, $0) })
        var current = byName[attempt.courseFile]
        if current == nil {
            current = files.first { $0.deletingPathExtension().lastPathComponent == attempt.lesson }
        }
        guard let current,
            !customCourses.contains(current.lastPathComponent),
            !attempt.customCourse,
            let currentNumber = Self.leadingNumber(current.deletingPathExtension().lastPathComponent)
        else { return nil }
        let candidates = files.compactMap { url -> (Int, URL)? in
            if url == current || customCourses.contains(url.lastPathComponent) { return nil }
            guard let n = Self.leadingNumber(url.deletingPathExtension().lastPathComponent), n > currentNumber else { return nil }
            return (n, url)
        }
        .sorted { $0.0 == $1.0 ? $0.1.lastPathComponent.caseInsensitiveCompare($1.1.lastPathComponent) == .orderedAscending : $0.0 < $1.0 }
        return candidates.first?.1
    }

    func openLesson(url: URL) {
        let stem = url.deletingPathExtension().lastPathComponent
        if courseNames.contains(stem) { selectedLesson = stem }
        selectedTab = .lesson
        prepareLesson()
    }

    func returnToLesson() {
        if courseNames.contains(lastLessonName) { selectedLesson = lastLessonName }
        selectedTab = .lesson
        prepareLesson()
    }

    // MARK: - Reviewing History

    var historySummary: String {
        guard !history.isEmpty else { return t("no_attempts") }
        let best = history.map(\.wpm).max() ?? 0
        let avg = history.map(\.accuracy).reduce(0, +) / Double(history.count)
        return t("history_summary", args: [
            "count": "\(history.count)",
            "best": speedUnit.format(best),
            "unit": t(speedUnit.unitKey),
            "accuracy": String(format: "%.1f", avg),
        ])
    }

    func clearHistory() {
        history.removeAll()
        AppSupport.writeJSON(history, to: AppSupport.historyFile)
    }

    // MARK: - Importing and Editing Lessons

    /// Import external `.txt` files with encoding sniffing (replaces the
    /// Tk file dialog in `import_course`).
    func importCourses(urls: [URL]) {
        var last: String? = nil
        for source in urls {
            let scoped = source.startAccessingSecurityScopedResource()
            defer { if scoped { source.stopAccessingSecurityScopedResource() } }
            let destination = AppSupport.courses.appendingPathComponent(source.lastPathComponent)
            do {
                let text = try CourseText.read(source)
                try text.write(to: destination, atomically: true, encoding: .utf8)
                last = destination.deletingPathExtension().lastPathComponent
                customCourses.insert(destination.lastPathComponent)
            } catch {
                noticeTitleKey = "import_failed_title"
                noticeMessage = t("import_failed_body", args: ["name": source.lastPathComponent, "error": error.localizedDescription])
            }
        }
        if let last {
            AppSupport.writeJSON(Array(customCourses).sorted(), to: AppSupport.customCoursesFile)
            reloadCourses(select: last)
        }
    }

    func loadEditorFromSelection() {
        guard let url = currentURL() else { return }
        do {
            editorName = url.deletingPathExtension().lastPathComponent
            editorText = try CourseText.read(url)
        } catch {
            noticeTitleKey = "lesson_load_failed_title"
            noticeMessage = t("lesson_load_failed_body", args: ["name": url.lastPathComponent, "error": error.localizedDescription])
        }
    }

    func newEditorLesson() {
        editorName = ""
        editorText = ""
    }

    /// Save the editor buffer. Returns false and shows a notice on failure.
    @discardableResult
    func saveEditorLesson(confirmReplace: Bool, alreadyConfirmed: Bool = false) -> Bool {
        let safe = editorName.filter { $0.isLetter || $0.isNumber || $0 == " " || $0 == "-" || $0 == "_" }
            .trimmingCharacters(in: .whitespaces)
        guard !safe.isEmpty, !editorText.isEmpty else {
            noticeTitleKey = "cannot_save_title"
            noticeMessage = t("cannot_save_body")
            return false
        }
        let path = AppSupport.courses.appendingPathComponent(safe + ".txt")
        if FileManager.default.fileExists(atPath: path.path),
            path.deletingPathExtension().lastPathComponent != selectedLesson,
            confirmReplace, !alreadyConfirmed
        {
            return false
        }
        do {
            try editorText.write(to: path, atomically: true, encoding: .utf8)
        } catch {
            noticeTitleKey = "cannot_save_title"
            noticeMessage = error.localizedDescription
            return false
        }
        if !AppSupport.builtinCourseFiles.contains(path.lastPathComponent) {
            customCourses.insert(path.lastPathComponent)
            AppSupport.writeJSON(Array(customCourses).sorted(), to: AppSupport.customCoursesFile)
        }
        reloadCourses(select: safe)
        noticeTitleKey = "lesson_saved_title"
        noticeMessage = t("lesson_saved_body", args: ["name": path.lastPathComponent])
        return true
    }

    // MARK: - Scoring Results

    func overallScore(for attempt: Attempt) -> Double {
        let speed = min(attempt.wpm / max(1, settings.goalWpm) * 100, 100)
        return max(0, min(100, (attempt.accuracy + speed + (100 - attempt.slowdown)) / 3))
    }

    // MARK: - Private

    private func playKey(correct: Bool) {
        if settings.sound { sound.play(correct: correct) }
    }

    private func isoNow() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: Date())
    }

    private static func leadingNumber(_ stem: String) -> Int? {
        let prefix = stem.prefix(while: \.isNumber)
        return Int(prefix)
    }

    private static func word(at index: Int, in text: String) -> String? {
        guard !text.isEmpty else { return nil }
        let chars = Array(text)
        guard index < chars.count, !chars[index].isWhitespace else { return "" }
        var start = index
        while start > 0, !chars[start - 1].isWhitespace { start -= 1 }
        var end = index
        while end < chars.count, !chars[end].isWhitespace { end += 1 }
        return String(chars[start..<end])
    }
}

// MARK: - Selecting Tabs

enum AppTab: String, Hashable, Sendable, CaseIterable {
    case lesson
    case stats
    case editor
}

// MARK: - Character Helpers

private extension Character {
    var isPrintableASCIIOrBeyond: Bool {
        if unicodeScalars.count != 1 { return true }
        let v = unicodeScalars.first!.value
        return v >= 32 && v != 127
    }
}
