import Foundation

enum TaskStatus: String, Codable {
    case pending
    case running
    case succeeded
    case failed
    case cancelled
}

struct ScheduledTask: Identifiable, Codable, Equatable {
    let id: UUID
    var prompt: String
    var projectName: String
    /// Absolute filesystem path to the project folder. Used by the automator
    /// to set Claude's working folder via the picker's "Open folder…" entry,
    /// which is far more reliable than name-matching dropdown items.
    var folderPath: String?
    /// When true, Claude session is switched to "Auto mode" before the prompt
    /// is submitted. Otherwise the current mode (usually "Accept edits") is left
    /// untouched.
    var autoMode: Bool
    var scheduledAt: Date
    var status: TaskStatus
    var log: [LogEntry]
    var failureReason: String?
    var startedAt: Date?
    var completedAt: Date?

    init(
        id: UUID = UUID(),
        prompt: String,
        projectName: String,
        folderPath: String? = nil,
        autoMode: Bool = false,
        scheduledAt: Date,
        status: TaskStatus = .pending,
        log: [LogEntry] = [],
        failureReason: String? = nil,
        startedAt: Date? = nil,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.prompt = prompt
        self.projectName = projectName
        self.folderPath = folderPath
        self.autoMode = autoMode
        self.scheduledAt = scheduledAt
        self.status = status
        self.log = log
        self.failureReason = failureReason
        self.startedAt = startedAt
        self.completedAt = completedAt
    }

    // Custom decoder so older saved tasks (which predate `autoMode`) keep
    // loading. `decodeIfPresent` defaults the new field to false.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.prompt = try c.decode(String.self, forKey: .prompt)
        self.projectName = try c.decode(String.self, forKey: .projectName)
        self.folderPath = try c.decodeIfPresent(String.self, forKey: .folderPath)
        self.autoMode = try c.decodeIfPresent(Bool.self, forKey: .autoMode) ?? false
        self.scheduledAt = try c.decode(Date.self, forKey: .scheduledAt)
        self.status = try c.decode(TaskStatus.self, forKey: .status)
        self.log = try c.decode([LogEntry].self, forKey: .log)
        self.failureReason = try c.decodeIfPresent(String.self, forKey: .failureReason)
        self.startedAt = try c.decodeIfPresent(Date.self, forKey: .startedAt)
        self.completedAt = try c.decodeIfPresent(Date.self, forKey: .completedAt)
    }
}

struct LogEntry: Codable, Equatable, Identifiable {
    let id: UUID
    let timestamp: Date
    let level: Level
    let message: String

    enum Level: String, Codable {
        case info, warning, error
    }

    init(level: Level, message: String) {
        self.id = UUID()
        self.timestamp = Date()
        self.level = level
        self.message = message
    }
}
