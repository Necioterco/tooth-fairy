import SwiftUI
import AppKit

struct AddTaskView: View {
    let onClose: () -> Void
    @EnvironmentObject var taskStore: TaskStore

    @State private var prompt: String = ""
    @State private var projectName: String = ""
    @State private var folderPath: String = ""
    @State private var autoMode: Bool = false
    @State private var scheduledAt: Date = defaultScheduleDate()

    private static func defaultScheduleDate() -> Date {
        let cal = Calendar.current
        var components = cal.dateComponents([.year, .month, .day], from: Date())
        components.hour = 22
        components.minute = 0
        let today10pm = cal.date(from: components) ?? Date().addingTimeInterval(3600)
        return today10pm < Date() ? cal.date(byAdding: .day, value: 1, to: today10pm)! : today10pm
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            ScrollView {
                form
                    .padding(20)
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
            Text("New scheduled task")
                .font(.headline)
            Spacer()
            // Invisible spacer to balance Back button visually
            Label("Back", systemImage: "chevron.left")
                .labelStyle(.titleAndIcon)
                .opacity(0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Project folder").font(.caption.bold()).foregroundStyle(.secondary)
                HStack {
                    TextField("/path/to/project", text: $folderPath)
                        .textFieldStyle(.roundedBorder)
                    Button("Choose…") { chooseFolder() }
                }
                if !recentFolders.isEmpty {
                    recentFoldersRow
                }
                if !projectName.isEmpty {
                    Text("Will appear in Claude as: \(projectName)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                } else {
                    Text("Pick the folder Claude should open before sending the prompt.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            scheduleSection

            VStack(alignment: .leading, spacing: 6) {
                Text("Prompt").font(.caption.bold()).foregroundStyle(.secondary)
                TextEditor(text: $prompt)
                    .font(.body)
                    .frame(minHeight: 140)
                    .padding(6)
                    .background(Color(NSColor.textBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.secondary.opacity(0.3))
                    )
            }

            Toggle(isOn: $autoMode) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Run in Auto mode")
                    Text("Switches the session to Auto mode (⇧⌘M → 4) before sending. Otherwise the current mode is left untouched.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .toggleStyle(.checkbox)

            HStack {
                Spacer()
                Button("Cancel") { onClose() }
                Button("Schedule") {
                    addTask()
                }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(!isValid)
            }
        }
    }

    private var isValid: Bool {
        !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !folderPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && scheduledAt > Date()
    }

    private func addTask() {
        let trimmedPath = folderPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = projectName.isEmpty ? (URL(fileURLWithPath: trimmedPath).lastPathComponent) : projectName
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: scheduledAt)
        let scheduledMinute = cal.date(from: comps) ?? scheduledAt
        let task = ScheduledTask(
            prompt: prompt,
            projectName: resolvedName,
            folderPath: trimmedPath,
            autoMode: autoMode,
            scheduledAt: scheduledMinute
        )
        taskStore.add(task)
        onClose()
    }

    // MARK: - Recent folders

    /// Distinct folder paths from prior tasks, ordered by most-recent use.
    /// Capped at 5 so the row stays compact.
    private var recentFolders: [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        let sortedTasks = taskStore.tasks.sorted { lhs, rhs in
            let l = lhs.completedAt ?? lhs.startedAt ?? lhs.scheduledAt
            let r = rhs.completedAt ?? rhs.startedAt ?? rhs.scheduledAt
            return l > r
        }
        for task in sortedTasks {
            guard let path = task.folderPath, !path.isEmpty else { continue }
            if seen.insert(path).inserted {
                ordered.append(path)
                if ordered.count >= 5 { break }
            }
        }
        return ordered
    }

    private var recentFoldersRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Text("Recent:")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                ForEach(recentFolders, id: \.self) { path in
                    let name = URL(fileURLWithPath: path).lastPathComponent
                    let isActive = path == folderPath
                    Button {
                        folderPath = path
                        projectName = name
                    } label: {
                        Text(name)
                            .font(.caption)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(isActive ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.12))
                            .foregroundStyle(isActive ? Color.accentColor : .primary)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help(path)
                }
            }
        }
    }

    // MARK: - Schedule UI

    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("When").font(.caption.bold()).foregroundStyle(.secondary)

            // Date row — calendar icon + day / month / year dropdowns.
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .foregroundStyle(.secondary)

                Picker("", selection: dayBinding) {
                    ForEach(1...daysInCurrentMonth, id: \.self) { d in
                        Text("\(d)").tag(d)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 64)

                Picker("", selection: monthBinding) {
                    ForEach(1...12, id: \.self) { m in
                        Text(monthName(m)).tag(m)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 110)

                Picker("", selection: yearBinding) {
                    ForEach(yearRange, id: \.self) { y in
                        Text(verbatim: String(y)).tag(y)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 80)

                Spacer()
            }

            // Time row — clock icon + hour / minute / AM-PM dropdowns.
            HStack(spacing: 6) {
                Image(systemName: "clock")
                    .foregroundStyle(.secondary)

                Picker("", selection: hourBinding) {
                    ForEach(1...12, id: \.self) { h in
                        Text(String(format: "%d", h)).tag(h)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 64)

                Text(":").foregroundStyle(.secondary)

                Picker("", selection: minuteBinding) {
                    ForEach([0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55], id: \.self) { m in
                        Text(String(format: "%02d", m)).tag(m)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 64)

                Picker("", selection: meridiemBinding) {
                    Text("AM").tag(false)
                    Text("PM").tag(true)
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 70)

                Spacer()
            }

            // Live preview — confirms the exact moment this task fires.
            Text(scheduleSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Date helpers

    private var daysInCurrentMonth: Int {
        let cal = Calendar.current
        return cal.range(of: .day, in: .month, for: scheduledAt)?.count ?? 31
    }

    private var yearRange: [Int] {
        let currentYear = Calendar.current.component(.year, from: Date())
        return Array(currentYear...(currentYear + 5))
    }

    private func monthName(_ m: Int) -> String {
        let f = DateFormatter()
        return f.monthSymbols[m - 1]
    }

    // MARK: - Date / time bindings (decompose / recompose `scheduledAt`)

    private var dayBinding: Binding<Int> {
        Binding(
            get: { Calendar.current.component(.day, from: scheduledAt) },
            set: { newDay in
                let cal = Calendar.current
                var comps = cal.dateComponents([.year, .month, .hour, .minute], from: scheduledAt)
                comps.day = newDay
                if let d = cal.date(from: comps) {
                    scheduledAt = d
                }
            }
        )
    }

    private var monthBinding: Binding<Int> {
        Binding(
            get: { Calendar.current.component(.month, from: scheduledAt) },
            set: { newMonth in
                let cal = Calendar.current
                var comps = cal.dateComponents([.year, .day, .hour, .minute], from: scheduledAt)
                comps.month = newMonth
                // Clamp the day if the new month has fewer days (Feb 31 → 28/29).
                if let firstOfMonth = cal.date(from: DateComponents(year: comps.year, month: newMonth, day: 1)),
                   let range = cal.range(of: .day, in: .month, for: firstOfMonth),
                   let day = comps.day,
                   day > range.count {
                    comps.day = range.count
                }
                if let d = cal.date(from: comps) {
                    scheduledAt = d
                }
            }
        )
    }

    private var yearBinding: Binding<Int> {
        Binding(
            get: { Calendar.current.component(.year, from: scheduledAt) },
            set: { newYear in
                let cal = Calendar.current
                var comps = cal.dateComponents([.month, .day, .hour, .minute], from: scheduledAt)
                comps.year = newYear
                // Re-clamp day for leap-year edge case (Feb 29 → Feb 28).
                if let m = comps.month,
                   let firstOfMonth = cal.date(from: DateComponents(year: newYear, month: m, day: 1)),
                   let range = cal.range(of: .day, in: .month, for: firstOfMonth),
                   let day = comps.day,
                   day > range.count {
                    comps.day = range.count
                }
                if let d = cal.date(from: comps) {
                    scheduledAt = d
                }
            }
        )
    }

    private var hourBinding: Binding<Int> {
        Binding(
            get: {
                let h = Calendar.current.component(.hour, from: scheduledAt) % 12
                return h == 0 ? 12 : h
            },
            set: { new12 in
                let cal = Calendar.current
                let was24 = cal.component(.hour, from: scheduledAt)
                let isPM = was24 >= 12
                let new24 = (new12 % 12) + (isPM ? 12 : 0)
                if let d = cal.date(bySetting: .hour, value: new24, of: scheduledAt) {
                    scheduledAt = d
                }
            }
        )
    }

    private var minuteBinding: Binding<Int> {
        Binding(
            get: { Calendar.current.component(.minute, from: scheduledAt) },
            set: { new in
                let cal = Calendar.current
                if let d = cal.date(bySetting: .minute, value: new, of: scheduledAt) {
                    scheduledAt = d
                }
            }
        )
    }

    private var meridiemBinding: Binding<Bool> {
        Binding(
            get: { Calendar.current.component(.hour, from: scheduledAt) >= 12 },
            set: { isPM in
                let cal = Calendar.current
                let was24 = cal.component(.hour, from: scheduledAt)
                let h12 = was24 % 12
                let new24 = h12 + (isPM ? 12 : 0)
                if let d = cal.date(bySetting: .hour, value: new24, of: scheduledAt) {
                    scheduledAt = d
                }
            }
        )
    }

    private var scheduleSummary: String {
        let absolute: String = {
            let f = DateFormatter()
            f.doesRelativeDateFormatting = true
            f.dateStyle = .full
            f.timeStyle = .short
            return f.string(from: scheduledAt)
        }()
        let relative: String = {
            let r = RelativeDateTimeFormatter()
            r.unitsStyle = .full
            return r.localizedString(for: scheduledAt, relativeTo: Date())
        }()
        return "Fires \(absolute) — \(relative)"
    }

    private func chooseFolder() {
        // Tell AppDelegate to keep the popover open across the modal sheet.
        // Without this, NSOpenPanel's activation makes the menu-bar popover
        // dismiss itself, forcing the user to click the menu bar icon again
        // after picking a folder.
        NotificationCenter.default.post(name: .toothFairySuspendDismiss, object: nil)
        defer {
            NotificationCenter.default.post(name: .toothFairyResumeDismiss, object: nil)
        }

        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            folderPath = url.path
            projectName = url.lastPathComponent
        }
    }
}

