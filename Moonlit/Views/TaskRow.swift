import SwiftUI
import AppKit

struct TaskRow: View {
    let task: ScheduledTask
    let onShowDetail: (UUID) -> Void
    @EnvironmentObject var taskStore: TaskStore
    @EnvironmentObject var scheduler: Scheduler

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            statusIcon
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(task.projectName)
                        .font(.caption.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.purple.opacity(0.15))
                        .foregroundStyle(.purple)
                        .clipShape(Capsule())
                    if task.autoMode {
                        Text("AUTO")
                            .font(.caption2.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.15))
                            .foregroundStyle(.blue)
                            .clipShape(Capsule())
                    }
                    Text(scheduleLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(task.prompt)
                    .font(.body)
                    .lineLimit(2)
                    .foregroundStyle(.primary)
                if let reason = task.failureReason, task.status == .failed {
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if task.status == .pending {
                Button {
                    scheduler.runNow(task)
                } label: {
                    Image(systemName: "play.fill")
                        .foregroundStyle(.purple)
                }
                .buttonStyle(.borderless)
                .help("Run now")
                .disabled(scheduler.isRunningTask)
            }

            Menu {
                if task.status == .pending {
                    Button("Run now") { scheduler.runNow(task) }
                }
                Button("View log") { onShowDetail(task.id) }
                Divider()
                Button("Delete", role: .destructive) {
                    taskStore.delete(task)
                }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture { onShowDetail(task.id) }
    }

    private var statusIcon: some View {
        Group {
            switch task.status {
            case .pending:
                Image(systemName: "clock").foregroundStyle(.orange)
            case .running:
                ProgressView().controlSize(.small)
            case .succeeded:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            case .failed:
                Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
            case .cancelled:
                Image(systemName: "minus.circle.fill").foregroundStyle(.gray)
            }
        }
        .font(.body)
    }

    private var scheduleLabel: String {
        let formatter = DateFormatter()
        formatter.doesRelativeDateFormatting = true
        formatter.dateStyle = .medium
        formatter.timeStyle = .short

        switch task.status {
        case .pending:
            return "Scheduled \(formatter.string(from: task.scheduledAt))"
        case .running:
            if let started = task.startedAt {
                return "Started \(formatter.string(from: started))"
            }
            return "Running"
        case .succeeded, .failed, .cancelled:
            let when = task.completedAt ?? task.startedAt ?? task.scheduledAt
            let prefix = task.status == .succeeded ? "Ran" : task.status == .failed ? "Failed" : "Cancelled"
            return "\(prefix) \(formatter.string(from: when))"
        }
    }
}
