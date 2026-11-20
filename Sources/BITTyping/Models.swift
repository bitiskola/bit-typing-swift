import Foundation

// MARK: - Describing Typing Behavior

/// Typo handling modes. Raw values match the strings stored in
/// `settings.json` so files stay compatible with the original app.
enum TypoMode: String, Codable, CaseIterable, Sendable {
    case typeRight = "Type the right character"
    case backspace = "Correct with Backspace"
    case cont = "Continue"
}

/// Per-character result state. Absence from `Session.states` means pending.
enum CharState: String, Codable, Sendable {
    case correct
    case timeout
    case error
    case errorTimeout
}

struct Stroke: Codable, Sendable {
    var expected: String
    var actual: String
    var timestamp: Double
    var delay: Double
    var correct: Bool
    var timedOut: Bool
    var index: Int
    var systemKey: Bool = false
}

// MARK: - Tracking a Lesson Session

/// Live typing state. Mirrors the `Session` dataclass in `main.py`.
struct Session: Sendable {
    var lesson: String = ""
    var text: String = ""
    var characters: [Character] = []
    var index: Int = 0
    var startedWall: String = ""
    var startedAt: Date? = nil
    var pausedAt: Date? = nil
    var pausedTotal: TimeInterval = 0
    var lastKeyAt: Date? = nil
    var running: Bool = false
    var paused: Bool = false
    var errors: Int = 0
    var timeouts: Int = 0
    var backspaces: Int = 0
    var typedKeys: Int = 0
    var correctKeys: Int = 0
    var fixedIndices: Set<Int> = []
    var pendingWrong: Bool = false
    var states: [Int: CharState] = [:]
    var strokes: [Stroke] = []
    /// Time already spent before this run, when continuing an unfinished
    /// attempt. Counted into `elapsed()` so the clock picks up where it was.
    var resumedElapsed: TimeInterval = 0

    // MARK: - Measuring Elapsed Time

    func elapsed(now: Date = Date()) -> TimeInterval {
        guard let startedAt else { return resumedElapsed }
        let end = paused ? (pausedAt ?? now) : now
        return resumedElapsed + max(0, end.timeIntervalSince(startedAt) - pausedTotal)
    }
}

// MARK: - Storing Attempts

/// A finished lesson attempt. Coding keys match the original `history.json`.
struct Attempt: Codable, Identifiable, Sendable {
    var id: UUID = UUID()
    var lesson: String = ""
    var startedAt: String = ""
    var courseFile: String = ""
    var customCourse: Bool = false
    var finishedAt: String = ""
    var duration: Double = 0
    var wpm: Double = 0
    var accuracy: Double = 100
    var slowdown: Double = 0
    var done: Double = 0
    var words: Int = 0
    var fixedWords: Int = 0
    var characters: Int = 0
    var fixedCharacters: Int = 0
    var errors: Int = 0
    var timeouts: Int = 0
    var backspaces: Int = 0
    var passed: Bool = false
    var text: String = ""
    var states: [String: CharState] = [:]
    var strokes: [Stroke] = []
    /// Finished early: can be continued from Statistics, and finishing the
    /// continuation updates this row in place.
    var unfinished: Bool = false
    /// Stable course id (`local:<stem>` / `repo:<slug>:<layout>:<stem>`) so a
    /// continued attempt finds its lesson again.
    var courseID: String = ""
    /// Backspace-repaired indices, restored when continuing.
    var fixedIndices: [Int] = []

    enum CodingKeys: String, CodingKey {
        case lesson
        case startedAt = "started_at"
        case courseFile = "course_file"
        case customCourse = "custom_course"
        case finishedAt = "finished_at"
        case duration
        case wpm
        case accuracy
        case slowdown
        case done
        case words
        case fixedWords = "fixed_words"
        case characters
        case fixedCharacters = "fixed_characters"
        case errors
        case timeouts
        case backspaces
        case passed
        case text
        case states
        case strokes
        case unfinished
        case courseID = "course_id"
        case fixedIndices = "fixed_indices"
    }

    // MARK: - Reading Character States

    func state(at index: Int) -> CharState? {
        states[String(index)]
    }
}

// MARK: - Decoding Older History

extension Attempt {
    /// Every key is optional so `history.json` files written by older
    /// versions (without `unfinished`, `course_id`, …) still load instead
    /// of silently resetting the whole history.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        lesson = try c.decodeIfPresent(String.self, forKey: .lesson) ?? lesson
        startedAt = try c.decodeIfPresent(String.self, forKey: .startedAt) ?? startedAt
        courseFile = try c.decodeIfPresent(String.self, forKey: .courseFile) ?? courseFile
        customCourse = try c.decodeIfPresent(Bool.self, forKey: .customCourse) ?? customCourse
        finishedAt = try c.decodeIfPresent(String.self, forKey: .finishedAt) ?? finishedAt
        duration = try c.decodeIfPresent(Double.self, forKey: .duration) ?? duration
        wpm = try c.decodeIfPresent(Double.self, forKey: .wpm) ?? wpm
        accuracy = try c.decodeIfPresent(Double.self, forKey: .accuracy) ?? accuracy
        slowdown = try c.decodeIfPresent(Double.self, forKey: .slowdown) ?? slowdown
        done = try c.decodeIfPresent(Double.self, forKey: .done) ?? done
        words = try c.decodeIfPresent(Int.self, forKey: .words) ?? words
        fixedWords = try c.decodeIfPresent(Int.self, forKey: .fixedWords) ?? fixedWords
        characters = try c.decodeIfPresent(Int.self, forKey: .characters) ?? characters
        fixedCharacters = try c.decodeIfPresent(Int.self, forKey: .fixedCharacters) ?? fixedCharacters
        errors = try c.decodeIfPresent(Int.self, forKey: .errors) ?? errors
        timeouts = try c.decodeIfPresent(Int.self, forKey: .timeouts) ?? timeouts
        backspaces = try c.decodeIfPresent(Int.self, forKey: .backspaces) ?? backspaces
        passed = try c.decodeIfPresent(Bool.self, forKey: .passed) ?? passed
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? text
        states = try c.decodeIfPresent([String: CharState].self, forKey: .states) ?? states
        strokes = try c.decodeIfPresent([Stroke].self, forKey: .strokes) ?? strokes
        unfinished = try c.decodeIfPresent(Bool.self, forKey: .unfinished) ?? unfinished
        courseID = try c.decodeIfPresent(String.self, forKey: .courseID) ?? courseID
        fixedIndices = try c.decodeIfPresent([Int].self, forKey: .fixedIndices) ?? fixedIndices
    }
}

// MARK: - Managing Settings

struct AppSettings: Codable, Sendable {
    var setupComplete: Bool = false
    var typoMode: TypoMode = .typeRight
    var backspace: Bool = true
    var goalWpm: Double = 30
    var goalAccuracy: Double = 95
    var timeoutSeconds: Double = 1.6
    var timedMinutes: Double = 0
    var metronome: Bool = false
    var sound: Bool = false
    var autoStart: Bool = true
    var language: String = "EN-us"
    var keyboardLayout: String = "US-qwerty"

    enum CodingKeys: String, CodingKey {
        case setupComplete = "setup_complete"
        case typoMode = "typo_mode"
        case backspace
        case goalWpm = "goal_wpm"
        case goalAccuracy = "goal_accuracy"
        case timeoutSeconds = "timeout_seconds"
        case timedMinutes = "timed_minutes"
        case metronome
        case sound
        case autoStart = "auto_start"
        case language
        case keyboardLayout = "keyboard_layout"
    }
}

// MARK: - Loading Resource Packs

struct LanguagePack: Codable, Sendable {
    var name: String = ""
    var defaultKeyboard: String = ""

    var strings: [String: String] = [:]

    enum CodingKeys: String, CodingKey {
        case name
        case defaultKeyboard = "default_keyboard"
        case strings
    }
}

struct KeyboardLayout: Codable, Sendable, Equatable {
    var name: String = ""
    var rows: [[String]] = []
    var spaceLabel: String = "SPACE"

    enum CodingKeys: String, CodingKey {
        case name
        case rows
        case spaceLabel = "space_label"
    }
}
