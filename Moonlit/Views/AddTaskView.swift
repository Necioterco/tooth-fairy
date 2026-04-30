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

    // MARK: - Schedule UI

    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("When").font(.caption.bold()).foregroundStyle(.secondary)

            // Calendar grid — way easier to scan than a numeric date field.
            DatePicker(
                "",
                selection: $scheduledAt,
                in: Date()...,
                displayedComponents: .date
            )
            .labelsHidden()
            .datePickerStyle(.graphical)
            .frame(maxWidth: .infinity)

            // Time as three menu pickers — hour, minute, AM/PM. Each opens a
            // dropdown on click, no fiddly steppers or text fields.
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

    // MARK: - Time bindings (decompose / recompose `scheduledAt`)

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

