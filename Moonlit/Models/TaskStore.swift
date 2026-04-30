import Foundation
import Combine

@MainActor
final class TaskStore: ObservableObject {
    @Published var tasks: [ScheduledTask] = []

    private let fileURL: URL

    init() {
        let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = supportDir.appendingPathComponent("Tooth Fairy", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        // Migrate any pre-rename data from the old "Moonlit" support folder
        // so existing users don't lose their scheduled tasks.
        let legacyDir = supportDir.appendingPathComponent("Moonlit", isDirectory: true)
        let legacyFile = legacyDir.appendingPathComponent("tasks.json")
        let newFile = appDir.appendingPathComponent("tasks.json")
        if FileManager.default.fileExists(atPath: legacyFile.path),
           !FileManager.default.fileExists(atPath: newFile.path) {
            try? FileManager.default.copyItem(at: legacyFile, to: newFile)
        }
        self.fileURL = newFile
        load()
    }

    func add(_ task: ScheduledTask) {
        tasks.append(task)
        save()
    }

    func update(_ task: ScheduledTask) {
        guard let idx = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[idx] = task
        save()
    }

    func delete(_ task: ScheduledTask) {
        tasks.removeAll { $0.id == task.id }
        save()
    }

    func appendLog(_ entry: LogEntry, to taskID: UUID) {
        guard let idx = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        tasks[idx].log.append(entry)
        save()
    }

    func setStatus(_ status: TaskStatus, for taskID: UUID, failureReason: String? = nil) {
        guard let idx = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        tasks[idx].status = status
        if status == .running {
            tasks[idx].startedAt = Date()
        }
        if status == .succeeded || status == .failed || status == .cancelled {
            tasks[idx].completedAt = Date()
        }
        if let reason = failureReason {
            tasks[idx].failureReason = reason
        }
        save()
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            tasks = try decoder.decode([ScheduledTask].self, from: data)
        } catch {
            print("[ToothFairy] failed to load tasks: \(error)")
        }
    }

    private func save() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(tasks)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("[ToothFairy] failed to save tasks: \(error)")
        }
    }
}
