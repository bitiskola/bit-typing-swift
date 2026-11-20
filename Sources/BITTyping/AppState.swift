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

    /// Configured course pack URLs (default pack always first/present).
    var courseRepos: [String] = []
    /// Local lessons plus pack lessons matching the keyboard layout.
    var availableCourses: [AvailableCourse] = []
    var selectedCourseID: String = ""
    var lastCourseID: String = ""
    var session = Session()
    /// History row being continued; finishing updates it in place.
    var continuingFromID: UUID? = nil
    var repoSummaries: [RepoSummary] = []
    var repoStatus: String = ""
    var refreshingRepos = false

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

    init(autoRefreshRepos: Bool = true) {
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
        courseRepos = CourseRepos.loadURLs()
        loadResources()
        refreshAvailable()
        prepareLesson()
        showingSetup = !settings.setupComplete
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        // Lessons from the local checkouts are usable immediately; packs
        // are pulled in the background and merged in when done.
        if autoRefreshRepos { refreshRepos() }
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

    /// Apply edited settings (Options / Setup) without restarting the
    /// lesson: the course list is only rebuilt when the keyboard layout
    /// changed, and the live session survives unless its course vanished.
    func applySettings(_ updated: AppSettings) {
        let oldLayout = settings.keyboardLayout
        let oldLanguage = settings.language
        settings = updated
        saveSettings()
        loadResources()
        if settings.keyboardLayout != oldLayout {
            courseListChanged()
        } else if session.characters.isEmpty, settings.language != oldLanguage {
            // Only the localized "no lesson" placeholder needs refreshing.
            prepareLesson()
        }
    }

    /// Opening Options/About must never silently keep the clock running.
    func pauseForModal() {
        guard session.running, !session.paused else { return }
        session.paused = true
        session.pausedAt = Date()
        startButtonKey = "resume"
        tipKey = "paused_tip"
    }

    func setSpeedUnit(_ unit: SpeedUnit) {
        speedUnit = unit
        UserDefaults.standard.set(unit.rawValue, forKey: "bittyping.speedUnit")
    }

    // MARK: - Managing Lessons

    var currentCourse: AvailableCourse? {
        availableCourses.first { $0.id == selectedCourseID }
    }

    /// Title for the window: the live session's lesson (which may be an
    /// orphaned continuation) or the picker selection.
    var lessonTitle: String {
        session.lesson.isEmpty ? (currentCourse?.title ?? "") : session.lesson
    }

    /// Rebuild the layout-filtered course list. Keeps the selection when it
    /// still exists. Returns true when the selection changed.
    @discardableResult
    func refreshAvailable(select: String? = nil) -> Bool {
        let previous = selectedCourseID
        availableCourses = CourseRepos.collectAvailable(
            urls: courseRepos, layout: settings.keyboardLayout, custom: customCourses)
        if let select {
            if availableCourses.contains(where: { $0.id == select }) {
                selectedCourseID = select
            } else if let match = availableCourses.first(where: { $0.title == select }) {
                selectedCourseID = match.id
            }
        }
        if !availableCourses.contains(where: { $0.id == selectedCourseID }) {
            selectedCourseID = availableCourses.first?.id ?? ""
        }
        repoSummaries = courseRepos.map { RepoSummary(url: $0, layout: settings.keyboardLayout) }
        return selectedCourseID != previous
    }

    /// The course list changed underneath (packs, layout): restart only
    /// when the selected lesson is gone or nothing is in progress, so an
    /// in-progress run is never wiped.
    private func courseListChanged() {
        let selectionChanged = refreshAvailable()
        if selectionChanged || (!session.running && continuingFromID == nil) {
            prepareLesson()
        }
    }

    func selectCourse(_ id: String) {
        guard id != selectedCourseID || !session.running else { return }
        selectedCourseID = id
        prepareLesson()
    }

    func currentURL() -> URL? {
        guard let url = currentCourse?.url, FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    /// Reset state for the selected lesson without starting the clock.
    func prepareLesson() {
        // A fresh start always records a new history row.
        continuingFromID = nil
        if let course = currentCourse, let url = currentURL() {
            do {
                // Editors commonly leave one terminal newline; it must not
                // require an invisible final Enter press to finish.
                let raw = try CourseText.read(url)
                let text = raw.replacingOccurrences(of: "[\\r\\n]+$", with: "", options: .regularExpression)
                session = Session(lesson: course.title, text: text, characters: Array(text))
                lastCourseID = course.id
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

    /// Typing can (re)start: there is text left and the session is either
    /// live or not started yet (a finished run must be re-prepared first).
    var canStartLesson: Bool {
        !session.characters.isEmpty && session.index < session.characters.count
            && (session.running || session.startedAt == nil)
    }

    /// "Finish early" is offered once something was typed and text remains.
    var canFinishEarly: Bool {
        session.running && session.index > 0 && session.index < session.characters.count
    }

    func toggleStart() {
        guard canStartLesson else { return }
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
        // A continuation keeps the original start time of the row.
        if continuingFromID == nil || session.startedWall.isEmpty {
            session.startedWall = isoNow()
        }
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
                    canStartLesson,
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

    /// Stop before the last character: saves an `unfinished` row that can
    /// be continued later from Statistics (even after relaunching).
    func finishEarly() {
        guard canFinishEarly else { return }
        finishSession(early: true)
    }

    func finishSession(early: Bool = false) {
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

        // A continuation keeps its stored identifiers, so an attempt whose
        // pack was removed meanwhile can still be finished consistently.
        let continued = continuingFromID.flatMap { id in history.first { $0.id == id } }
        var courseFile = ""
        var custom = false
        var courseID = ""
        if let continued {
            courseFile = continued.courseFile
            custom = continued.customCourse
            courseID = continued.courseID
            if let live = availableCourses.first(where: { $0.id == continued.courseID }) {
                courseFile = live.courseFile
                custom = live.custom
            }
        } else if let course = currentCourse {
            courseFile = course.courseFile
            custom = course.custom
            courseID = course.id
        }
        let done = session.text.isEmpty ? 0 : Double(session.index) / Double(session.characters.count) * 100
        var attempt = Attempt(
            lesson: session.lesson,
            startedAt: session.startedWall,
            courseFile: courseFile,
            customCourse: custom,
            finishedAt: isoNow(),
            duration: duration,
            wpm: wpm,
            accuracy: accuracy,
            slowdown: slowdown,
            done: done,
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
            strokes: session.strokes,
            unfinished: early && done < 99.9 && !session.text.isEmpty,
            courseID: courseID,
            fixedIndices: session.fixedIndices.sorted()
        )
        if let continued, let index = history.firstIndex(where: { $0.id == continued.id }) {
            attempt.id = continued.id
            history[index] = attempt
        } else {
            history.append(attempt)
        }
        continuingFromID = nil
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

    /// Results closed without choosing an action: a finished run can't be
    /// typed into any more, so set the lesson up fresh.
    func resultsDismissed() {
        if !session.running, session.startedAt != nil {
            prepareLesson()
        }
    }

    private func sessionTextPrefixLength() -> Int {
        session.text.prefix(session.index).count
    }

    // MARK: - Continuing Unfinished Attempts

    /// Rebuild a session from an unfinished row so the rest can be typed.
    /// The clock resumes from the stored duration on the first keystroke
    /// (or Start), and finishing updates the same history row.
    func continueAttempt(_ id: UUID) {
        guard let attempt = history.first(where: { $0.id == id }), attempt.unfinished, !attempt.text.isEmpty else { return }
        // Prefer the live course; the stored transcript still works when
        // the pack was removed or renamed.
        let live = availableCourses.first { $0.id == attempt.courseID }
            ?? availableCourses.first { $0.courseFile == attempt.courseFile && $0.title == attempt.lesson }
        if let live {
            selectedCourseID = live.id
            lastCourseID = live.id
        }
        let characters = Array(attempt.text)
        var restored = Session(lesson: attempt.lesson, text: attempt.text, characters: characters)
        restored.index = min(attempt.characters, characters.count)
        for (key, state) in attempt.states {
            if let index = Int(key) { restored.states[index] = state }
        }
        restored.strokes = attempt.strokes
        restored.errors = attempt.errors
        restored.timeouts = attempt.timeouts
        restored.backspaces = attempt.backspaces
        let normal = attempt.strokes.filter { !$0.systemKey }
        restored.typedKeys = normal.count
        restored.correctKeys = normal.filter(\.correct).count
        restored.fixedIndices = Set(attempt.fixedIndices)
        restored.startedWall = attempt.startedAt
        restored.resumedElapsed = max(0, attempt.duration)
        session = restored
        continuingFromID = id
        resultsAttempt = nil
        selectedHistoryID = nil
        selectedTab = .lesson
        startButtonKey = "resume"
        tipKey = "ready_tip"
        updateLive()
    }

    // MARK: - Navigating Between Lessons

    /// Next numbered lesson in the same pack and layout. Unfinished runs
    /// never offer one: the lesson should be continued first.
    func nextCourse(for attempt: Attempt) -> AvailableCourse? {
        guard !attempt.unfinished else { return nil }
        var id = attempt.courseID
        if id.isEmpty || !availableCourses.contains(where: { $0.id == id }) {
            // Older rows only stored the file name.
            id = availableCourses.first { $0.courseFile == attempt.courseFile && $0.title == attempt.lesson }?.id
                ?? availableCourses.first { !$0.custom && $0.title == attempt.lesson }?.id
                ?? ""
        }
        return CourseRepos.nextCourse(in: availableCourses, after: id)
    }

    func openCourse(_ course: AvailableCourse) {
        selectedCourseID = course.id
        selectedTab = .lesson
        prepareLesson()
    }

    func returnToLesson() {
        if availableCourses.contains(where: { $0.id == lastCourseID }) { selectedCourseID = lastCourseID }
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
            localLessonChanged("local:\(last)")
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
            selectedCourseID != "local:\(safe)",
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
        customCourses.insert(path.lastPathComponent)
        AppSupport.writeJSON(Array(customCourses).sorted(), to: AppSupport.customCoursesFile)
        localLessonChanged("local:\(safe)")
        noticeTitleKey = "lesson_saved_title"
        noticeMessage = t("lesson_saved_body", args: ["name": path.lastPathComponent])
        return true
    }

    /// Select a just-written local lesson. Its new text is loaded unless a
    /// different lesson is mid-run.
    private func localLessonChanged(_ id: String) {
        let previous = selectedCourseID
        refreshAvailable(select: id)
        if selectedCourseID != previous || !session.running || previous == id {
            prepareLesson()
        }
    }

    // MARK: - Managing Course Packs

    /// Clone/pull every pack in the background, then merge the result into
    /// the course list without disturbing an in-progress lesson.
    func refreshRepos() {
        guard !refreshingRepos else { return }
        refreshingRepos = true
        let urls = courseRepos
        Task {
            let results = await Task.detached { await CourseRepos.refreshAll(urls) }.value
            refreshingRepos = false
            courseListChanged()
            var ok = 0
            var firstError: String? = nil
            for (_, result) in results {
                switch result {
                case .success: ok += 1
                case .failure(let error): if firstError == nil { firstError = error.message }
                }
            }
            if let firstError {
                repoStatus = "\(t("repo_refresh_partial")): \(firstError)"
            } else {
                repoStatus = t("repo_refreshed", args: ["count": "\(ok)"])
            }
        }
    }

    /// Clone a new pack; it is only added to the list when the fetch worked.
    /// Returns true on success.
    func addRepo(_ raw: String) async -> Bool {
        let url = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else {
            repoStatus = t("repo_empty_url")
            return false
        }
        let normalized = CourseRepos.normalize(url).lowercased()
        guard !courseRepos.contains(where: { CourseRepos.normalize($0).lowercased() == normalized }) else {
            repoStatus = t("repo_already_added")
            return false
        }
        let slug = CourseRepos.slug(for: url)
        // Packs are stored by folder name; two URLs ending in the same name
        // would overwrite each other's checkout.
        guard !courseRepos.contains(where: { CourseRepos.slug(for: $0) == slug }) else {
            repoStatus = "\(t("repo_add_failed")): \(slug)"
            return false
        }
        guard !refreshingRepos else { return false }
        refreshingRepos = true
        let result = await Task.detached { await CourseRepos.refresh(url: url) }.value
        refreshingRepos = false
        switch result {
        case .success(let details):
            courseRepos.append(url)
            CourseRepos.saveURLs(courseRepos)
            courseListChanged()
            repoStatus = t("repo_added", args: ["name": details.name.isEmpty ? url : details.name])
            return true
        case .failure(let error):
            repoStatus = "\(t("repo_add_failed")): \(error.message)"
            return false
        }
    }

    func removeRepo(_ url: String) {
        guard !CourseRepos.isDefault(url) else {
            repoStatus = t("repo_default_locked")
            return
        }
        courseRepos.removeAll { $0 == url }
        // Drop the checkout so its lessons leave the picker.
        try? FileManager.default.removeItem(at: CourseRepos.directory(for: url))
        CourseRepos.saveURLs(courseRepos)
        courseListChanged()
        repoStatus = t("repo_removed", args: ["name": url])
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
    case repos
}

// MARK: - Summarizing Course Packs

/// One row of the course pack page.
struct RepoSummary: Identifiable, Sendable {
    var url: String
    var slug: String
    var name: String
    var creator: String
    var isDefault: Bool
    /// The checkout exists locally.
    var downloaded: Bool
    /// Lessons for the active keyboard layout / in total.
    var matchingCount: Int
    var totalCount: Int

    var id: String { url }

    init(url: String, layout: String) {
        self.url = url
        slug = CourseRepos.slug(for: url)
        isDefault = CourseRepos.isDefault(url)
        let directory = CourseRepos.directory(for: url)
        downloaded = FileManager.default.fileExists(atPath: directory.path)
        let details = downloaded ? CourseRepos.details(in: directory, slug: slug) : RepoDetails()
        name = details.name.isEmpty ? slug : details.name
        creator = details.creator
        totalCount = details.courses.count
        matchingCount = details.courses.filter {
            $0.layout == "*" || $0.layout.caseInsensitiveCompare(layout) == .orderedSame
        }.count
    }
}

// MARK: - Character Helpers

private extension Character {
    var isPrintableASCIIOrBeyond: Bool {
        if unicodeScalars.count != 1 { return true }
        let v = unicodeScalars.first!.value
        return v >= 32 && v != 127
    }
}
