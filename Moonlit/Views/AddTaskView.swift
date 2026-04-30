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
        VStack(alignment: .leading, spacing: 8) {
            Text("When").font(.caption.bold()).foregroundStyle(.secondary)

            // Quick presets — one tap = done in the common cases.
            HStack(spacing: 6) {
                ForEach(SchedulePreset.allCases, id: \.self) { preset in
                    presetChip(preset)
                }
            }

            // Always-visible date + time pickers for custom adjustments.
            HStack(spacing: 10) {
                DatePicker("", selection: $scheduledAt, in: Date()..., displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.field)
                DatePicker("", selection: $scheduledAt, in: Date()..., displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .datePickerStyle(.stepperField)
            }

            // Live preview so you always know exactly when this will fire.
            HStack(spacing: 4) {
                Image(systemName: "clock")
                    .font(.caption2)
                Text(scheduleSummary)
                    .font(.caption)
            }
            .foregroundStyle(.secondary)
        }
    }

    private func presetChip(_ preset: SchedulePreset) -> some View {
        let isActive = preset.matches(scheduledAt)
        return Button {
            scheduledAt = preset.date(from: Date())
        } label: {
            Text(preset.label)
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(isActive ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.10))
                .foregroundStyle(isActive ? Color.accentColor : .primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
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

/// Quick "when" presets surfaced as chips at the top of the schedule section.
/// Each option computes a concrete date relative to "now", so picking one
/// always gives a sensible, near-future time without the user touching the
/// date/time pickers.
enum SchedulePreset: CaseIterable {
    case in30min
    case in1hour
    case tonight
    case tomorrowMorning

    var label: String {
        switch self {
        case .in30min:          return "In 30 min"
        case .in1hour:          return "In 1 hour"
        case .tonight:          return "Tonight 10 PM"
        case .tomorrowMorning:  return "Tomorrow 9 AM"
        }
    }

    func date(from now: Date) -> Date {
        let cal = Calendar.current
        switch self {
        case .in30min:
            return cal.date(byAdding: .minute, value: 30, to: now) ?? now
        case .in1hour:
            return cal.date(byAdding: .hour, value: 1, to: now) ?? now
        case .tonight:
            var comps = cal.dateComponents([.year, .month, .day], from: now)
            comps.hour = 22
            comps.minute = 0
            let target = cal.date(from: comps) ?? now
            // If 10pm has already passed, push to tomorrow night.
            return target > now ? target : (cal.date(byAdding: .day, value: 1, to: target) ?? target)
        case .tomorrowMorning:
            let tomorrow = cal.date(byAdding: .day, value: 1, to: now) ?? now
            var comps = cal.dateComponents([.year, .month, .day], from: tomorrow)
            comps.hour = 9
            comps.minute = 0
            return cal.date(from: comps) ?? tomorrow
        }
    }

    /// True if `date` is within a minute of this preset's computed value.
    /// Used to highlight the active chip.
    func matches(_ date: Date) -> Bool {
        let target = self.date(from: Date())
        return abs(date.timeIntervalSince(target)) < 60
    }
}
