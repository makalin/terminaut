import Foundation

protocol CoreClientProtocol {
    func normalize(path: String) throws -> String
    func listDirectory(path: String) throws -> [DirectoryEntry]
    func listFavorites() throws -> [String]
    func addFavorite(path: String) throws
    func removeFavorite(path: String) throws
    func listRecents() throws -> [RecentEntry]
    func touchRecent(path: String) throws
    func detectProjects(path: String) throws -> [ProjectRoot]
    func listTags() throws -> [TaggedPath]
    func tags(for path: String) throws -> [TaggedPath]
    func addTag(path: String, label: String, color: String) throws
    func removeTag(path: String, label: String) throws
    func listProfiles() throws -> [LaunchProfile]
    func saveProfile(id: UUID?, name: String, command: String?, workingDir: String?, terminal: String?, windows: Int) throws -> LaunchProfile
    func deleteProfile(id: UUID) throws
    func search(start: String, query: String, limit: Int) throws -> [SearchResult]
}

enum CoreClientError: LocalizedError {
    case binaryNotFound
    case commandFailed(String)
    case decodeFailed

    var errorDescription: String? {
        switch self {
        case .binaryNotFound:
            return "Unable to locate term-core-cli. Build it with `cargo build -p term-core-cli`."
        case .commandFailed(let message):
            return "term-core-cli failed: \(message)"
        case .decodeFailed:
            return "Failed to decode data from term-core-cli."
        }
    }
}

final class RustCoreClient: CoreClientProtocol {
    private let executableURL: URL
    private let decoder = JSONDecoder()

    init(binaryURL: URL? = nil) throws {
        guard let url = try Self.locateBinary(explicit: binaryURL) else {
            throw CoreClientError.binaryNotFound
        }
        self.executableURL = url
    }

    func normalize(path: String) throws -> String {
        try runString(["normalize", path])
    }

    func listDirectory(path: String) throws -> [DirectoryEntry] {
        try runJSON(["list", path])
    }

    func listFavorites() throws -> [String] {
        try runJSON(["favorites", "list"])
    }

    func addFavorite(path: String) throws {
        _ = try runJSON(["favorites", "add", path]) as [String: String]
    }

    func removeFavorite(path: String) throws {
        _ = try runJSON(["favorites", "remove", path]) as [String: String]
    }

    func listRecents() throws -> [RecentEntry] {
        try runJSON(["recents", "list"])
    }

    func touchRecent(path: String) throws {
        _ = try runJSON(["recents", "touch", path]) as [String: String]
    }

    func detectProjects(path: String) throws -> [ProjectRoot] {
        try runJSON(["projects", path])
    }

    func listTags() throws -> [TaggedPath] {
        try runJSON(["tags", "list"])
    }

    func tags(for path: String) throws -> [TaggedPath] {
        try runJSON(["tags", "for", path])
    }

    func addTag(path: String, label: String, color: String) throws {
        _ = try runJSON(["tags", "add", path, label, "--color", color]) as [String: String]
    }

    func removeTag(path: String, label: String) throws {
        _ = try runJSON(["tags", "remove", path, label]) as [String: String]
    }

    func listProfiles() throws -> [LaunchProfile] {
        try runJSON(["profiles", "list"])
    }

    func saveProfile(id: UUID?, name: String, command: String?, workingDir: String?, terminal: String?, windows: Int) throws -> LaunchProfile {
        var args = ["profiles", "save", name]
        if let id { args += ["--id", id.uuidString] }
        if let command, !command.isEmpty { args += ["--command", command] }
        if let workingDir, !workingDir.isEmpty { args += ["--working-dir", workingDir] }
        if let terminal, !terminal.isEmpty { args += ["--terminal", terminal] }
        if windows > 0 { args += ["--windows", String(windows)] }
        return try runJSON(args)
    }

    func deleteProfile(id: UUID) throws {
        _ = try runJSON(["profiles", "delete", id.uuidString]) as [String: String]
    }

    func search(start: String, query: String, limit: Int) throws -> [SearchResult] {
        try runJSON(["search", query, "--start", start, "--limit", String(limit)])
    }

    private func runString(_ arguments: [String]) throws -> String {
        let data = try run(arguments)
        guard let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            throw CoreClientError.decodeFailed
        }
        return output
    }

    private func runJSON<T: Decodable>(_ arguments: [String]) throws -> T {
        let data = try run(arguments)
        return try decoder.decode(T.self, from: data)
    }

    private func run(_ arguments: [String]) throws -> Data {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let err = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "unknown error"
            throw CoreClientError.commandFailed(err.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return stdout.fileHandleForReading.readDataToEndOfFile()
    }

    private static func locateBinary(explicit: URL?) throws -> URL? {
        if let explicit {
            return explicit
        }
        let fm = FileManager.default
        var candidates: [URL] = []
        let env = ProcessInfo.processInfo.environment
        if let override = env["TERMINAUT_CORE_BIN"] {
            candidates.append(URL(fileURLWithPath: override))
        }
        if let bundleURL = Bundle.main.url(forAuxiliaryExecutable: "term-core-cli") {
            candidates.append(bundleURL)
        }
        let cwd = URL(fileURLWithPath: fm.currentDirectoryPath)
        candidates.append(URL(fileURLWithPath: "../../target/debug/term-core-cli", relativeTo: cwd).standardizedFileURL)
        candidates.append(URL(fileURLWithPath: "../../target/release/term-core-cli", relativeTo: cwd).standardizedFileURL)
        let bundleURL = Bundle.main.bundleURL
        let bundleDir = bundleURL.deletingLastPathComponent().standardizedFileURL
        candidates.append(bundleDir.appendingPathComponent("term-core-cli"))
        candidates.append(bundleDir.deletingLastPathComponent().appendingPathComponent("term-core-cli"))
        for url in candidates {
            if fm.isExecutableFile(atPath: url.path) {
                return url
            }
        }
        return nil
    }
}

final class FallbackCoreClient: CoreClientProtocol {
    private let fm = FileManager.default
    private var tags: [TaggedPath] = []
    private var profiles: [LaunchProfile] = []

    func normalize(path: String) throws -> String {
        (path as NSString).expandingTildeInPath
    }

    func listDirectory(path: String) throws -> [DirectoryEntry] {
        let url = URL(fileURLWithPath: try normalize(path: path))
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .contentModificationDateKey]
        let contents = try fm.contentsOfDirectory(at: url, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles])
        return contents.map { fileURL in
            let vals = try? fileURL.resourceValues(forKeys: keys)
            let isDir = vals?.isDirectory ?? false
            let modDate = vals?.contentModificationDate
            return DirectoryEntry(name: fileURL.lastPathComponent, path: fileURL.path, isDirectory: isDir, modificationDate: modDate)
        }.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    func listFavorites() throws -> [String] { [] }
    func addFavorite(path: String) throws {}
    func removeFavorite(path: String) throws {}
    func listRecents() throws -> [RecentEntry] { [] }
    func touchRecent(path: String) throws {}
    func detectProjects(path: String) throws -> [ProjectRoot] { [] }

    func listTags() throws -> [TaggedPath] { tags }

    func tags(for path: String) throws -> [TaggedPath] {
        let normalized = try normalize(path: path)
        return tags.filter { $0.path == normalized }
    }

    func addTag(path: String, label: String, color: String) throws {
        let normalized = try normalize(path: path)
        if let index = tags.firstIndex(where: { $0.path == normalized && $0.tag.caseInsensitiveCompare(label) == .orderedSame }) {
            tags[index] = TaggedPath(path: normalized, tag: label, color: color)
        } else {
            tags.append(TaggedPath(path: normalized, tag: label, color: color))
        }
    }

    func removeTag(path: String, label: String) throws {
        let normalized = try normalize(path: path)
        tags.removeAll { $0.path == normalized && $0.tag.caseInsensitiveCompare(label) == .orderedSame }
    }

    func listProfiles() throws -> [LaunchProfile] { profiles }

    func saveProfile(id: UUID?, name: String, command: String?, workingDir: String?, terminal: String?, windows: Int) throws -> LaunchProfile {
        let profile = LaunchProfile(id: id ?? UUID(), name: name, command: command, workingDir: workingDir, terminal: terminal, windows: UInt8(max(1, windows)))
        if let idx = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[idx] = profile
        } else {
            profiles.append(profile)
        }
        return profile
    }

    func deleteProfile(id: UUID) throws {
        profiles.removeAll { $0.id == id }
    }

    func search(start: String, query: String, limit: Int) throws -> [SearchResult] {
        if query.trimmingCharacters(in: .whitespaces).isEmpty {
            return []
        }
        let normalized = try normalize(path: start)
        let enumerator = fm.enumerator(atPath: normalized)
        var results: [SearchResult] = []
        while let item = enumerator?.nextObject() as? String {
            if results.count >= limit { break }
            if item.lowercased().contains(query.lowercased()) {
                results.append(SearchResult(path: (normalized as NSString).appendingPathComponent(item), name: (item as NSString).lastPathComponent, score: Int64(query.count)))
            }
        }
        return results
    }
}
