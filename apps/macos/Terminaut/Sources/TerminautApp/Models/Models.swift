import Foundation

struct DirectoryEntry: Identifiable, Codable {
    var id: String { path }
    let name: String
    let path: String
    let isDirectory: Bool
    let modificationDate: Date?

    enum CodingKeys: String, CodingKey {
        case name
        case path
        case isDirectory = "is_dir"
        case modificationDate = "mod_date"
    }

    init(name: String, path: String, isDirectory: Bool, modificationDate: Date? = nil) {
        self.name = name
        self.path = path
        self.isDirectory = isDirectory
        self.modificationDate = modificationDate
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        path = try c.decode(String.self, forKey: .path)
        isDirectory = try c.decode(Bool.self, forKey: .isDirectory)
        if let secs = try c.decodeIfPresent(Int64.self, forKey: .modificationDate) {
            modificationDate = Date(timeIntervalSince1970: TimeInterval(secs))
        } else {
            modificationDate = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(path, forKey: .path)
        try c.encode(isDirectory, forKey: .isDirectory)
        if let d = modificationDate {
            try c.encode(Int64(d.timeIntervalSince1970), forKey: .modificationDate)
        }
    }

    var fileExtension: String {
        (path as NSString).pathExtension.lowercased()
    }

    var sortKind: String {
        if isDirectory { return "Folder" }
        return fileExtension.isEmpty ? "Document" : fileExtension
    }
}

struct RecentEntry: Identifiable, Codable {
    var id: String { path }
    let path: String
    let lastOpenedUTC: Int64

    enum CodingKeys: String, CodingKey {
        case path
        case lastOpenedUTC = "last_opened_utc"
    }

    var displayDate: Date {
        Date(timeIntervalSince1970: TimeInterval(lastOpenedUTC))
    }
}

struct ProjectRoot: Identifiable, Codable {
    var id: String { path }
    let path: String
    let marker: String
}

struct TaggedPath: Identifiable, Codable, Hashable {
    var id: String { "\(path)::\(tag.lowercased())" }
    let path: String
    let tag: String
    let color: String
}

struct LaunchProfile: Identifiable, Codable {
    let id: UUID
    let name: String
    let command: String?
    let workingDir: String?
    let terminal: String?
    let windows: UInt8

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case command
        case workingDir = "working_dir"
        case terminal
        case windows
    }

    init(id: UUID, name: String, command: String?, workingDir: String?, terminal: String?, windows: UInt8) {
        self.id = id
        self.name = name
        self.command = command
        self.workingDir = workingDir
        self.terminal = terminal
        self.windows = windows
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let idString = try container.decode(String.self, forKey: .id)
        guard let uuid = UUID(uuidString: idString) else {
            throw DecodingError.dataCorruptedError(forKey: .id, in: container, debugDescription: "Invalid UUID")
        }
        id = uuid
        name = try container.decode(String.self, forKey: .name)
        command = try container.decodeIfPresent(String.self, forKey: .command)
        workingDir = try container.decodeIfPresent(String.self, forKey: .workingDir)
        terminal = try container.decodeIfPresent(String.self, forKey: .terminal)
        windows = try container.decodeIfPresent(UInt8.self, forKey: .windows) ?? 1
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id.uuidString, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(command, forKey: .command)
        try container.encodeIfPresent(workingDir, forKey: .workingDir)
        try container.encodeIfPresent(terminal, forKey: .terminal)
        try container.encode(windows, forKey: .windows)
    }
}

struct SearchResult: Identifiable, Codable {
    var id: String { path }
    let path: String
    let name: String
    let score: Int64
}
