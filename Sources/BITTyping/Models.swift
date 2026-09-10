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

    // MARK: - Measuring Elapsed Time

    func elapsed(now: Date = Date()) -> TimeInterval {
        guard let startedAt else { return 0 }
        let end = paused ? (pausedAt ?? now) : now
        return max(0, end.timeIntervalSince(startedAt) - pausedTotal)
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
    }

    // MARK: - Reading Character States

    func state(at index: Int) -> CharState? {
        states[String(index)]
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

struct KeyboardLayout: Codable, Sendable {
    var name: String = ""
    var rows: [[String]] = []
    var spaceLabel: String = "SPACE"

    enum CodingKeys: String, CodingKey {
        case name
        case rows
        case spaceLabel = "space_label"
    }
}
