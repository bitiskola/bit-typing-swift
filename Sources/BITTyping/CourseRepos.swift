import Foundation

// MARK: - Describing Course Packs

/// One course file inside a pack, as declared by `details.json`.
struct RepoCourse: Sendable, Hashable {
    var layout: String
    var path: String
    var title: String?
}

/// Parsed `details.json` of a course pack.
struct RepoDetails: Sendable {
    var name: String = ""
    var creator: String = ""
    var courses: [RepoCourse] = []
}

/// A lesson the user can pick: a local `courses/*.txt` file or a file from
/// a course pack. Port of `AvailableCourse` in the Rust version.
struct AvailableCourse: Identifiable, Hashable, Sendable {
    /// Stable id: `local:<stem>` or `repo:<slug>:<layout>:<stem>`.
    var id: String
    /// Short name shown in the picker.
    var title: String
    /// Pack display name (empty for local files).
    var repoName: String
    /// Keyboard layout this course belongs to (`*` = every layout).
    var layout: String
    var url: URL
    /// Identifier stored in history (file name for local lessons).
    var courseFile: String
    /// User-created local lesson (no *Next lesson* chaining).
    var custom: Bool

    /// Pack courses carry their pack name so equal file names in two packs
    /// stay distinguishable.
    var display: String {
        repoName.isEmpty ? title : "\(title) (\(repoName))"
    }
}

struct RepoError: Error, Sendable {
    var message: String
}

// MARK: - Managing Course Packs

/// Git-backed lesson packs filtered by keyboard layout. Port of `repos.rs`.
///
/// Pack layout on disk (`<root>/repos/<slug>/`):
/// ```text
/// details.json
/// HU-qwertz/01.txt
/// US-qwerty/01.txt
/// ```
/// `details.json` maps layouts to files, either as
/// `{"courses": {"HU-qwertz": ["HU-qwertz/01.txt"]}}` or as a list of
/// `{"layout": …, "path": …, "title": …}` entries. Packs without a usable
/// `details.json` fall back to scanning `<layout>/*.txt` folders.
enum CourseRepos {
    /// Built-in pack. Always configured, never removable.
    static let defaultURL = "https://github.com/bitiskola/bit-typing-main"

    // MARK: - Naming Packs

    /// Strip trailing separators and `.git` so equivalent URLs compare equal.
    static func normalize(_ url: String) -> String {
        var value = url.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.hasSuffix("/") || value.hasSuffix("\\") { value.removeLast() }
        if value.lowercased().hasSuffix(".git") { value.removeLast(4) }
        return value
    }

    static func isDefault(_ url: String) -> Bool {
        normalize(url) == normalize(defaultURL)
    }

    /// Filesystem-safe folder name for a pack URL (`…/bit-typing-main` → `bit-typing-main`).
    static func slug(for url: String) -> String {
        let clean = normalize(url)
        let last = clean.split(whereSeparator: { $0 == "/" || $0 == "\\" }).last.map(String.init) ?? "repo"
        var slug = String(
            last.trimmingCharacters(in: .whitespaces).map { char -> Character in
                char.isLetter || char.isNumber || char == "-" || char == "_" || char == "." ? char : "-"
            })
        slug = slug.trimmingCharacters(in: CharacterSet(charactersIn: "-._"))
        if slug.isEmpty { slug = "repo" }
        return String(slug.prefix(64))
    }

    static func directory(for url: String) -> URL {
        AppSupport.repos.appendingPathComponent(slug(for: url), isDirectory: true)
    }

    // MARK: - Storing the Pack List

    /// Configured URLs. Accepts `["url"]` and `[{"url": …}]`; the default
    /// pack is always present (first when it had to be added).
    static func loadURLs() -> [String] {
        var urls: [String] = []
        if let data = try? Data(contentsOf: AppSupport.reposFile),
            let items = (try? JSONSerialization.jsonObject(with: data)) as? [Any]
        {
            for item in items {
                let value = (item as? String) ?? ((item as? [String: Any])?["url"] as? String) ?? ""
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { urls.append(trimmed) }
            }
        }
        return withDefault(urls)
    }

    static func saveURLs(_ urls: [String]) {
        AppSupport.writeJSON(withDefault(urls), to: AppSupport.reposFile)
    }

    private static func withDefault(_ urls: [String]) -> [String] {
        var out = urls
        if !out.contains(where: isDefault) { out.insert(defaultURL, at: 0) }
        var seen: Set<String> = []
        return out.filter { seen.insert(normalize($0)).inserted }
    }

    // MARK: - Reading Pack Details

    static func parseDetails(_ data: Data) throws -> RepoDetails {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw RepoError(message: "details.json is not an object")
        }
        var details = RepoDetails(
            name: object["name"] as? String ?? "",
            creator: object["creator"] as? String ?? ""
        )
        // `layouts` is accepted as an alias for `courses`.
        for key in ["courses", "layouts"] {
            for entry in courseEntries(object[key]) where !details.courses.contains(where: { $0.layout == entry.layout && $0.path == entry.path }) {
                details.courses.append(entry)
            }
        }
        return details
    }

    private static func courseEntries(_ value: Any?) -> [RepoCourse] {
        var out: [RepoCourse] = []
        func push(_ layout: String, _ path: String, _ title: String?) {
            let layout = layout.trimmingCharacters(in: .whitespaces)
            let path = path.trimmingCharacters(in: .whitespaces)
            guard !layout.isEmpty, !path.isEmpty else { return }
            out.append(RepoCourse(layout: layout, path: path, title: title))
        }
        if let map = value as? [String: Any] {
            for layout in map.keys.sorted() {
                for file in (map[layout] as? [Any]) ?? [] {
                    if let file = file as? String { push(layout, file, nil) }
                }
            }
        } else if let list = value as? [Any] {
            for case let entry as [String: Any] in list {
                let path = (entry["path"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? entry["file"] as? String ?? ""
                let title = (entry["title"] as? String) ?? (entry["name"] as? String)
                push(entry["layout"] as? String ?? "", path, title)
            }
        }
        return out
    }

    static func loadDetails(_ directory: URL) -> RepoDetails? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("details.json")) else { return nil }
        return try? parseDetails(data)
    }

    /// Without a usable `details.json`, every `<layout>/*.txt` folder is
    /// that layout's pack.
    static func scanFallback(_ directory: URL, slug: String) -> RepoDetails {
        let manager = FileManager.default
        var details = RepoDetails(name: slug)
        let folders = (try? manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        for folder in folders {
            let layout = folder.lastPathComponent
            guard !layout.hasPrefix("."),
                (try? folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            else { continue }
            let files = (try? manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            for file in files where file.pathExtension.lowercased() == "txt" {
                details.courses.append(RepoCourse(layout: layout, path: "\(layout)/\(file.lastPathComponent)"))
            }
        }
        details.courses.sort { ($0.layout, $0.path) < ($1.layout, $1.path) }
        return details
    }

    static func details(in directory: URL, slug: String) -> RepoDetails {
        guard let parsed = loadDetails(directory) else {
            return scanFallback(directory, slug: slug)
        }
        if !parsed.courses.isEmpty { return parsed }
        // Empty course list: let the folder scan contribute.
        var scanned = scanFallback(directory, slug: slug)
        guard !scanned.courses.isEmpty else { return parsed }
        if !parsed.name.isEmpty { scanned.name = parsed.name }
        if scanned.creator.isEmpty { scanned.creator = parsed.creator }
        return scanned
    }

    // MARK: - Syncing Packs

    /// Clone a missing pack or pull an existing one. When the network or git
    /// fails, a usable local copy is still served, so lessons keep working
    /// offline.
    static func refresh(url: String) async -> Result<RepoDetails, RepoError> {
        let manager = FileManager.default
        let slug = slug(for: url)
        let destination = directory(for: url)
        try? manager.createDirectory(at: AppSupport.repos, withIntermediateDirectories: true)
        let git = gitExecutable()
        let hasCheckout = manager.fileExists(atPath: destination.appendingPathComponent(".git").path)

        if hasCheckout, let git, run(git, ["-C", destination.path, "rev-parse", "--git-dir"]).status == 0 {
            let pull = run(git, ["-C", destination.path, "pull", "--ff-only"])
            return serveLocal(destination, slug: slug, failure: pull.status == 0 ? nil : pull.output, fallback: "git pull failed")
        }
        // Missing, seeded snapshot, or a checkout git rejects (interrupted
        // clone): fetch into a temp folder and swap it in, so a failed
        // download never destroys usable local files.
        let fetched = await fetch(url: url, slug: slug, git: git)
        switch fetched {
        case .success(let temp):
            if swap(temp, into: destination, slug: slug) {
                return .success(details(in: destination, slug: slug))
            }
            try? manager.removeItem(at: temp)
            return serveLocal(destination, slug: slug, failure: "could not replace course checkout", fallback: "")
        case .failure(let error):
            return serveLocal(destination, slug: slug, failure: error.message, fallback: "")
        }
    }

    /// Refresh every pack. Per-pack results let the UI report stale ones.
    static func refreshAll(_ urls: [String]) async -> [(String, Result<RepoDetails, RepoError>)] {
        var results: [(String, Result<RepoDetails, RepoError>)] = []
        for url in urls {
            results.append((url, await refresh(url: url)))
        }
        return results
    }

    // MARK: - Listing Lessons

    /// Every local lesson (all layouts) plus each pack course matching
    /// `layout`, sorted by title then pack name. A pack with nothing for
    /// `layout` (e.g. the HU-only default pack on US-qwerty) lists all of
    /// its lessons instead, tagged with their layout, so the picker is
    /// never empty just because of the keyboard setting.
    static func collectAvailable(urls: [String], layout: String, custom: Set<String>) -> [AvailableCourse] {
        let manager = FileManager.default
        var out: [AvailableCourse] = []
        let locals = (try? manager.contentsOfDirectory(at: AppSupport.courses, includingPropertiesForKeys: nil)) ?? []
        for file in locals where file.pathExtension.lowercased() == "txt" {
            let stem = file.deletingPathExtension().lastPathComponent
            guard !stem.isEmpty else { continue }
            out.append(AvailableCourse(
                id: "local:\(stem)", title: stem, repoName: "", layout: "*", url: file,
                courseFile: file.lastPathComponent, custom: custom.contains(file.lastPathComponent)
            ))
        }
        for url in urls {
            let slug = slug(for: url)
            let directory = directory(for: url)
            guard manager.fileExists(atPath: directory.path) else { continue }
            let details = details(in: directory, slug: slug)
            let packName = details.name.isEmpty ? slug : details.name
            let matching = details.courses.filter { layoutMatches($0.layout, layout) }
            let showAllLayouts = matching.isEmpty
            for entry in showAllLayouts ? details.courses : matching {
                let repoName = showAllLayouts ? "\(packName) · \(entry.layout)" : packName
                let file = directory.appendingPathComponent(entry.path)
                guard manager.fileExists(atPath: file.path) else { continue }
                let fallback = file.deletingPathExtension().lastPathComponent
                let title = entry.title.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 } ?? fallback
                guard !title.isEmpty else { continue }
                out.append(AvailableCourse(
                    id: "repo:\(slug):\(entry.layout):\(title)", title: title, repoName: repoName,
                    layout: entry.layout, url: file,
                    courseFile: "\(slug):\(entry.layout):\(file.lastPathComponent)", custom: false
                ))
            }
        }
        return out.sorted {
            let lhs = ($0.title.lowercased(), $0.repoName.lowercased(), $0.id)
            let rhs = ($1.title.lowercased(), $1.repoName.lowercased(), $1.id)
            return lhs < rhs
        }
    }

    /// Next numbered lesson inside the same pack and layout.
    static func nextCourse(in available: [AvailableCourse], after id: String) -> AvailableCourse? {
        guard let current = available.first(where: { $0.id == id }), !current.custom,
            let number = leadingNumber(current.title)
        else { return nil }
        return available
            .filter { !$0.custom && $0.repoName == current.repoName && $0.layout == current.layout && $0.id != current.id }
            .compactMap { course -> (Int, AvailableCourse)? in
                guard let n = leadingNumber(course.title), n > number else { return nil }
                return (n, course)
            }
            .min { $0.0 == $1.0 ? $0.1.title.lowercased() < $1.1.title.lowercased() : $0.0 < $1.0 }?
            .1
    }

    // MARK: - Private

    private static func layoutMatches(_ entry: String, _ filter: String) -> Bool {
        let filter = filter.trimmingCharacters(in: .whitespaces)
        return filter.isEmpty || entry == "*" || entry.caseInsensitiveCompare(filter) == .orderedSame
    }

    private static func leadingNumber(_ stem: String) -> Int? {
        Int(stem.prefix(while: { $0.isASCII && $0.isNumber }))
    }

    private static func serveLocal(_ directory: URL, slug: String, failure: String?, fallback: String) -> Result<RepoDetails, RepoError> {
        let local = FileManager.default.fileExists(atPath: directory.path)
            ? details(in: directory, slug: slug) : RepoDetails()
        if failure == nil || !local.courses.isEmpty { return .success(local) }
        let message = failure?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return .failure(RepoError(message: message.isEmpty ? fallback : message))
    }

    /// Download a pack into a hidden temp folder next to its checkout.
    private static func fetch(url: String, slug: String, git: String?) async -> Result<URL, RepoError> {
        let manager = FileManager.default
        let temp = AppSupport.repos.appendingPathComponent(".\(slug).fetch", isDirectory: true)
        try? manager.removeItem(at: temp)
        if let git {
            let clone = run(git, ["clone", "--depth", "1", url, temp.path])
            if clone.status == 0 { return .success(temp) }
            try? manager.removeItem(at: temp)
            return .failure(RepoError(message: clone.output.isEmpty ? "git clone failed" : clone.output))
        }
        // No git on this Mac: GitHub packs still work through the archive
        // endpoint (refreshes re-download instead of pulling).
        guard let archive = githubArchiveURL(url) else {
            return .failure(RepoError(message: "git is not available. Install the Xcode Command Line Tools (xcode-select --install) to add non-GitHub packs."))
        }
        do {
            let (downloaded, response) = try await URLSession.shared.download(from: archive)
            defer { try? manager.removeItem(at: downloaded) }
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                return .failure(RepoError(message: "download failed (HTTP \(http.statusCode))"))
            }
            let unpacked = AppSupport.repos.appendingPathComponent(".\(slug).unzip", isDirectory: true)
            try? manager.removeItem(at: unpacked)
            defer { try? manager.removeItem(at: unpacked) }
            let unzip = run("/usr/bin/ditto", ["-x", "-k", downloaded.path, unpacked.path])
            guard unzip.status == 0 else { return .failure(RepoError(message: "unzip failed: \(unzip.output)")) }
            // GitHub wraps the tree in a single `<repo>-<ref>/` folder.
            let entries = (try? manager.contentsOfDirectory(at: unpacked, includingPropertiesForKeys: nil)) ?? []
            let visible = entries.filter { !$0.lastPathComponent.hasPrefix(".") && $0.lastPathComponent != "__MACOSX" }
            let tree = visible.count == 1 ? visible[0] : unpacked
            try manager.moveItem(at: tree, to: temp)
            return .success(temp)
        } catch {
            try? manager.removeItem(at: temp)
            return .failure(RepoError(message: error.localizedDescription))
        }
    }

    /// Replace `destination` with `temp`, restoring the old copy on failure.
    private static func swap(_ temp: URL, into destination: URL, slug: String) -> Bool {
        let manager = FileManager.default
        let backup = AppSupport.repos.appendingPathComponent(".\(slug).backup", isDirectory: true)
        try? manager.removeItem(at: backup)
        let hadOld = manager.fileExists(atPath: destination.path)
        if hadOld {
            guard (try? manager.moveItem(at: destination, to: backup)) != nil else { return false }
        }
        if (try? manager.moveItem(at: temp, to: destination)) != nil {
            try? manager.removeItem(at: backup)
            return true
        }
        if hadOld { try? manager.moveItem(at: backup, to: destination) }
        return false
    }

    private static func githubArchiveURL(_ url: String) -> URL? {
        guard let components = URLComponents(string: normalize(url)),
            let host = components.host?.lowercased(), host == "github.com" || host == "www.github.com"
        else { return nil }
        let parts = components.path.split(separator: "/").map(String.init)
        guard parts.count >= 2 else { return nil }
        return URL(string: "https://codeload.github.com/\(parts[0])/\(parts[1])/zip/HEAD")
    }

    /// A git binary that works without side effects. `/usr/bin/git` is an
    /// Xcode shim that pops an install dialog when no developer tools exist,
    /// so it is only used once `xcode-select -p` confirms they do. GUI apps
    /// don't inherit the shell PATH, so Homebrew locations are probed too.
    private static func gitExecutable() -> String? {
        let manager = FileManager.default
        for path in ["/opt/homebrew/bin/git", "/usr/local/bin/git"] where manager.isExecutableFile(atPath: path) {
            if run(path, ["--version"]).status == 0 { return path }
        }
        if run("/usr/bin/xcode-select", ["-p"]).status == 0, run("/usr/bin/git", ["--version"]).status == 0 {
            return "/usr/bin/git"
        }
        return nil
    }

    /// Run a tool synchronously, capturing combined output. Git never
    /// prompts for credentials (a private URL fails instead of hanging).
    private static func run(_ executable: String, _ arguments: [String]) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment["GIT_TERMINAL_PROMPT"] = "0"
        process.environment = environment
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return (-1, error.localizedDescription)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return (process.terminationStatus, output)
    }
}
