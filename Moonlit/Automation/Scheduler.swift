import Foundation
import Combine
import UserNotifications

@MainActor
final class Scheduler: ObservableObject {
    private let taskStore: TaskStore
    private let automator = ClaudeAutomator()
    private var timer: Timer?
    @Published var isRunningTask: Bool = false

    init(taskStore: TaskStore) {
        self.taskStore = taskStore
        requestNotificationPermission()
        start()
    }

    func start() {
        timer?.invalidate()
        // Check every 15 seconds. Fine resolution for night tasks.
        timer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        timer?.tolerance = 5.0
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard !isRunningTask else { return }
        let now = Date()
        let due = taskStore.tasks
            .filter { $0.status == .pending && $0.scheduledAt <= now }
            .sorted { $0.scheduledAt < $1.scheduledAt }
        guard let next = due.first else { return }
        run(next)
    }

    /// Run a task immediately, regardless of schedule. Used by the "Run now" button.
    func runNow(_ task: ScheduledTask) {
        guard !isRunningTask else { return }
        run(task)
    }

    private func run(_ task: ScheduledTask) {
        isRunningTask = true
        taskStore.setStatus(.running, for: task.id)
        taskStore.appendLog(LogEntry(level: .info, message: "Task started"), to: task.id)

        // Run on main actor — AX APIs require main thread, and our automator is @MainActor.
        Task { @MainActor in
            defer { isRunningTask = false }
            do {
                try automator.runScheduledTask(
                    prompt: task.prompt,
                    projectName: task.projectName,
                    folderPath: task.folderPath,
                    autoMode: task.autoMode,
                    log: { [weak self] entry in
                        self?.taskStore.appendLog(entry, to: task.id)
                    }
                )
                taskStore.setStatus(.succeeded, for: task.id)
                taskStore.appendLog(LogEntry(level: .info, message: "Task succeeded"), to: task.id)
                notify(title: "Tooth Fairy ✓", body: shortPreview(of: task.prompt))
            } catch let error as AutomationError {
                let reason = error.errorDescription ?? "\(error)"
                taskStore.setStatus(.failed, for: task.id, failureReason: reason)
                taskStore.appendLog(LogEntry(level: .error, message: reason), to: task.id)
                notify(title: "Tooth Fairy failed", body: reason)
            } catch {
                let reason = "\(error)"
                taskStore.setStatus(.failed, for: task.id, failureReason: reason)
                taskStore.appendLog(LogEntry(level: .error, message: reason), to: task.id)
                notify(title: "Tooth Fairy failed", body: reason)
            }
        }
    }

    private func shortPreview(of text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 80 { return trimmed }
        return String(trimmed.prefix(77)) + "…"
    }

    // MARK: Notifications

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func notify(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
