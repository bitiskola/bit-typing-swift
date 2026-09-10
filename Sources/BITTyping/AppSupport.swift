import Foundation

// MARK: - Locating Writable Storage

/// Writable per-user root: `~/Library/Application Support/BIT Typing`.
/// Bundled defaults ship in the app package and are seeded here without
/// overwriting user-edited files — mirroring `ensure_dirs()` in `main.py`.
enum AppSupport {
    static let appName = "BIT Typing"

    static var root: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return base.appendingPathComponent(appName, isDirectory: true)
    }

    static var courses: URL { root.appendingPathComponent("courses", isDirectory: true) }
    static var languages: URL { root.appendingPathComponent("lang", isDirectory: true) }
    static var keyboards: URL { root.appendingPathComponent("keyboards", isDirectory: true) }
    static var data: URL { root.appendingPathComponent("data", isDirectory: true) }
    static var sounds: URL { data.appendingPathComponent("sounds", isDirectory: true) }
    static var settingsFile: URL { data.appendingPathComponent("settings.json") }
    static var historyFile: URL { data.appendingPathComponent("history.json") }
    static var customCoursesFile: URL { data.appendingPathComponent("custom_courses.json") }

    static let builtinCourseFiles: Set<String> = [
        "01-Home-row.txt",
        "02-Common-words.txt",
        "03-Full-keyboard.txt",
    ]

    // MARK: - Seeding Bundled Defaults

    /// Copy bundled resources into Application Support on first launch.
    /// Courses are seeded once (user-editable), but lang/keyboards/sounds
    /// are app-owned and always refreshed — otherwise existing installs
    /// keep stale copies missing newer keys (e.g. `cpm_name`).
    static func ensureSeeded() {
        let manager = FileManager.default
        for dir in [courses, languages, keyboards, sounds] {
            try? manager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        try? manager.createDirectory(at: data, withIntermediateDirectories: true)
        seed(bundleName: "courses", destination: courses, extension: "txt", refresh: false)
        seed(bundleName: "lang", destination: languages, extension: "json", refresh: true)
        seed(bundleName: "keyboards", destination: keyboards, extension: "json", refresh: true)
        seed(bundleName: "sounds", destination: sounds, extension: "wav", refresh: true)
    }

    private static func seed(bundleName: String, destination: URL, extension ext: String, refresh: Bool) {
        let manager = FileManager.default
        guard let source = Bundle.module.resourceURL?.appendingPathComponent(bundleName, isDirectory: true),
            let files = try? manager.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)
        else { return }
        for file in files where file.pathExtension.lowercased() == ext {
            let target = destination.appendingPathComponent(file.lastPathComponent)
            if manager.fileExists(atPath: target.path) {
                guard refresh else { continue }
                try? manager.removeItem(at: target)
            }
            try? manager.copyItem(at: file, to: target)
        }
    }

    // MARK: - Reading and Writing JSON

    static func readJSON<T: Decodable>(_ url: URL, as type: T.Type, default defaultValue: T) -> T {
        guard let data = try? Data(contentsOf: url) else { return defaultValue }
        let decoder = JSONDecoder()
        return (try? decoder.decode(T.self, from: data)) ?? defaultValue
    }

    static func writeJSON<T: Encodable>(_ value: T, to url: URL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(value) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let temp = url.deletingLastPathComponent().appendingPathComponent(url.lastPathComponent + ".tmp")
        do {
            try data.write(to: temp, options: .atomic)
            _ = try? FileManager.default.replaceItemAt(url, withItemAt: temp)
            if !FileManager.default.fileExists(atPath: url.path) {
                try? FileManager.default.moveItem(at: temp, to: url)
            }
        } catch {
            try? data.write(to: url, options: .atomic)
        }
    }
}

// MARK: - Reading Lesson Text

/// Port of `read_course_text()` from `main.py`: honors BOMs, sniffs
/// BOM-less UTF-16/32 via NUL distribution, then falls back through
/// Central/Western European code pages to Latin-1 (which never fails).
enum CourseText {
    static func read(_ url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        if data.isEmpty { return "" }
        let bytes = [UInt8](data)
        if let text = decodeWithBOM(bytes) { return normalizeNewlines(text) }

        var encodings: [String.Encoding] = []
        let sample = Array(bytes.prefix(8192))
        if sample.count >= 8, let bomless32 = sniffUTF32(sample) {
            encodings.append(bomless32)
        }
        if sample.count >= 4, let bomless16 = sniffUTF16(sample) {
            encodings.append(bomless16)
        }
        encodings.append(contentsOf: [.utf8, .windowsCP1250, .windowsCP1252, .isoLatin1])
        for encoding in encodings {
            if let text = String(data: data, encoding: encoding) {
                return normalizeNewlines(text)
            }
        }
        return normalizeNewlines(String(data: data, encoding: .isoLatin1) ?? "")
    }

    // MARK: - Internal

    private static func decodeWithBOM(_ bytes: [UInt8]) -> String? {
        let data = Data(bytes)
        if bytes.starts(with: [0xFF, 0xFE, 0x00, 0x00]) || bytes.starts(with: [0x00, 0x00, 0xFE, 0xFF]) {
            return String(data: data, encoding: .utf32)
        }
        if bytes.starts(with: [0xFF, 0xFE]) || bytes.starts(with: [0xFE, 0xFF]) {
            return String(data: data, encoding: .utf16)
        }
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) {
            return String(data: data, encoding: .utf8)
        }
        return nil
    }

    private static func sniffUTF32(_ sample: [UInt8]) -> String.Encoding? {
        var ratios: [Double] = []
        for offset in 0..<4 {
            let lane = stride(from: offset, to: sample.count, by: 4).map { sample[$0] }
            guard !lane.isEmpty else { return nil }
            ratios.append(Double(lane.filter { $0 == 0 }.count) / Double(lane.count))
        }
        if ratios[1...].min() ?? 0 > 0.6 && ratios[0] < 0.4 { return .utf32LittleEndian }
        if ratios[..<3].min() ?? 0 > 0.6 && ratios[3] < 0.4 { return .utf32BigEndian }
        return nil
    }

    private static func sniffUTF16(_ sample: [UInt8]) -> String.Encoding? {
        let even = stride(from: 0, to: sample.count, by: 2).map { sample[$0] }
        let odd = stride(from: 1, to: sample.count, by: 2).map { sample[$0] }
        guard !even.isEmpty, !odd.isEmpty else { return nil }
        let evenNuls = Double(even.filter { $0 == 0 }.count) / Double(even.count)
        let oddNuls = Double(odd.filter { $0 == 0 }.count) / Double(odd.count)
        if oddNuls > 0.6 && evenNuls < 0.4 { return .utf16LittleEndian }
        if evenNuls > 0.6 && oddNuls < 0.4 { return .utf16BigEndian }
        return nil
    }

    private static func normalizeNewlines(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    }
}
