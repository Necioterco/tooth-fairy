import SwiftUI
import AppKit

enum MenuScreen: Equatable {
    case list
    case add
    case detail(UUID)
    case about
}

struct MenuBarView: View {
    @EnvironmentObject var taskStore: TaskStore
    @EnvironmentObject var scheduler: Scheduler
    @State private var permissionGranted = Accessibility.isGranted
    @State private var showingPast = false
    @State private var screen: MenuScreen = .list

    var body: some View {
        Group {
            switch screen {
            case .list:
                listScreen
            case .add:
                AddTaskView(onClose: { screen = .list })
                    .environmentObject(taskStore)
            case .detail(let id):
                TaskDetailView(taskID: id, onClose: { screen = .list })
                    .environmentObject(taskStore)
            case .about:
                AboutView(onClose: { screen = .list })
            }
        }
        .frame(width: 440)
        .frame(minHeight: 540, maxHeight: 640)
        .onAppear {
            permissionGranted = Accessibility.isGranted
        }
    }

    // MARK: - List screen

    private var listScreen: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
    }

    private var header: some View {
        HStack {
            Image(systemName: "moon.stars.fill")
                .foregroundStyle(.purple)
                .font(.title3)
            Text("Moonlit")
                .font(.title3.bold())
            Spacer()

            Menu {
                Button("Add scheduled task") { screen = .add }
                Divider()
                Button("About Moonlit") { screen = .about }
                Divider()
                Button("Quit") { NSApplication.shared.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    /// Full-bleed gated state shown in place of the scheduled section when
    /// Accessibility permission is missing. Past tasks still appear at the
    /// bottom of the popup so users can review history while gated.
    private var permissionGate: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 8)
            Image(systemName: "moon.zzz.fill")
                .font(.system(size: 44))
                .foregroundStyle(LinearGradient(
                    colors: [.purple, .indigo],
                    startPoint: .top,
                    endPoint: .bottom
                ))
            Text("Accessibility access needed")
                .font(.headline)
            Text("Moonlit needs Accessibility to control Claude desktop on your behalf.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 28)

            VStack(spacing: 6) {
                Button {
                    Accessibility.openSystemSettings()
                } label: {
                    Text("Open Accessibility Settings")
                        .frame(minWidth: 180)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)

                Button("Re-check") {
                    permissionGranted = Accessibility.isGranted
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            }
            Spacer(minLength: 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 16)
    }

    private var content: some View {
        VStack(spacing: 0) {
            if permissionGranted {
                ScrollView {
                    scheduledSection
                }
                .frame(maxHeight: .infinity)
            } else {
                permissionGate
            }

            if !pastTasks.isEmpty {
                // Divider only appears when the past section is expanded — when
                // collapsed, the toggle row sits flush against the bottom for a
                // cleaner look.
                if showingPast {
                    Divider()
                }
                pastSection
            }
        }
        .frame(minHeight: 260, maxHeight: 460)
    }

    private var scheduledSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(title: "Scheduled", count: scheduledTasks.count)
            if scheduledTasks.isEmpty {
                emptyScheduled
            } else {
                ForEach(scheduledTasks) { task in
                    TaskRow(task: task, onShowDetail: { id in screen = .detail(id) })
                        .environmentObject(taskStore)
                        .environmentObject(scheduler)
                    Divider()
                }
            }
        }
    }

    private var pastSection: some View {
        VStack(spacing: 0) {
            // Custom disclosure toggle — pinned to the bottom of the popup.
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    showingPast.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: showingPast ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("Past tasks")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Text("\(pastTasks.count)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .contentShape(Rectangle())
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)

            if showingPast {
                Divider()
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(pastTasks) { task in
                            TaskRow(task: task, onShowDetail: { id in screen = .detail(id) })
                                .environmentObject(taskStore)
                                .environmentObject(scheduler)
                            Divider()
                        }
                    }
                }
                .frame(maxHeight: 240)
            }
        }
    }

    private func sectionHeader(title: String, count: Int) -> some View {
        HStack {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            if count > 0 {
                Text("\(count)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 6)
    }

    private var emptyScheduled: some View {
        VStack(spacing: 12) {
            Image(systemName: "moon.zzz")
                .font(.title)
                .foregroundStyle(.tertiary)
            Text("Nothing scheduled")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button {
                screen = .add
            } label: {
                Label("Add scheduled task", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if scheduler.isRunningTask {
                ProgressView().controlSize(.small)
                Text("Running task…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let next = nextScheduledTask {
                Image(systemName: "clock")
                    .foregroundStyle(.purple)
                    .font(.caption)
                Text("Next: \(relative(next.scheduledAt))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "moon.fill")
                    .foregroundStyle(.tertiary)
                    .font(.caption)
                Text("Nothing scheduled")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                screen = .about
            } label: {
                Text(versionLabel)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help("About Moonlit")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var versionLabel: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        return "v\(v)"
    }

    // MARK: - Data

    private var scheduledTasks: [ScheduledTask] {
        taskStore.tasks
            .filter { $0.status == .pending || $0.status == .running }
            .sorted { $0.scheduledAt < $1.scheduledAt }
    }

    private var pastTasks: [ScheduledTask] {
        taskStore.tasks
            .filter { $0.status == .succeeded || $0.status == .failed || $0.status == .cancelled }
            .sorted { lhs, rhs in
                let l = lhs.completedAt ?? lhs.startedAt ?? lhs.scheduledAt
                let r = rhs.completedAt ?? rhs.startedAt ?? rhs.scheduledAt
                return l > r
            }
    }

    private var nextScheduledTask: ScheduledTask? {
        scheduledTasks.first { $0.status == .pending }
    }

    private func relative(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: Date())
    }
}
