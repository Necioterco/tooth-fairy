import SwiftUI

struct TaskDetailView: View {
    let taskID: UUID
    let onClose: () -> Void
    @EnvironmentObject var taskStore: TaskStore

    private var liveTask: ScheduledTask? {
        taskStore.tasks.first(where: { $0.id == taskID })
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            if let task = liveTask {
                detail(for: task)
            } else {
                missingState
            }
        }
    }

    private var headerBar: some View {
        HStack(spacing: 8) {
            Button {
                onClose()
            } label: {
                Label("Back", systemImage: "chevron.left")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.borderless)
            .keyboardShortcut(.escape)

            Spacer()
            Text("Task detail")
                .font(.headline)
            Spacer()
            Label("Back", systemImage: "chevron.left")
                .labelStyle(.titleAndIcon)
                .opacity(0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func detail(for task: ScheduledTask) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                metadata(for: task)
            }
            .padding(10)
            .background(Color.secondary.opacity(0.08))
            .cornerRadius(8)

            Text("Prompt")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            ScrollView {
                Text(task.prompt)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 90)
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(6)

            HStack {
                Text("Log")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(task.log.count) entries")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(task.log) { entry in
                        HStack(alignment: .top, spacing: 8) {
                            Text(timestamp(entry.timestamp))
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.tertiary)
                            Image(systemName: levelIcon(entry.level))
                                .foregroundStyle(levelColor(entry.level))
                                .font(.caption)
                            Text(entry.message)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                    }
                }
                .padding(8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(6)
        }
        .padding(16)
    }

    private var missingState: some View {
        VStack(spacing: 8) {
            Image(systemName: "questionmark.circle")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text("Task no longer exists")
                .foregroundStyle(.secondary)
            Button("Back to list") { onClose() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    private func metadata(for task: ScheduledTask) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Status:").foregroundStyle(.secondary)
                Text(task.status.rawValue.capitalized).bold()
            }
            HStack {
                Text("Project:").foregroundStyle(.secondary)
                Text(task.projectName)
            }
            if let path = task.folderPath, !path.isEmpty {
                HStack(alignment: .top) {
                    Text("Folder:").foregroundStyle(.secondary)
                    Text(path)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
            }
            if task.autoMode {
                HStack {
                    Text("Mode:").foregroundStyle(.secondary)
                    Text("Auto").bold()
                }
            }
            HStack {
                Text("Scheduled:").foregroundStyle(.secondary)
                Text(formatted(task.scheduledAt))
            }
            if let started = task.startedAt {
                HStack {
                    Text("Started:").foregroundStyle(.secondary)
                    Text(formatted(started))
                }
            }
            if let completed = task.completedAt {
                HStack {
                    Text("Completed:").foregroundStyle(.secondary)
                    Text(formatted(completed))
                }
            }
        }
        .font(.caption)
    }

    private func formatted(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .medium
        return f.string(from: date)
    }

    private func timestamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: date)
    }

    private func levelIcon(_ level: LogEntry.Level) -> String {
        switch level {
        case .info: return "info.circle"
        case .warning: return "exclamationmark.triangle"
        case .error: return "xmark.octagon"
        }
    }

    private func levelColor(_ level: LogEntry.Level) -> Color {
        switch level {
        case .info: return .blue
        case .warning: return .orange
        case .error: return .red
        }
    }
}
