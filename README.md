# Moonlit 🌙

A macOS menu bar app that schedules prompts to be sent to the Claude desktop app at specific times. Set it up before bed, wake up to completed sessions in your normal Claude app history.

## What it does

- Sits in your menu bar
- Lets you schedule a prompt + project + time
- At the scheduled time, drives the Claude desktop app via macOS Accessibility APIs to:
  1. Activate Claude desktop
  2. Switch to the Code tab
  3. Open a new session (⌘N)
  4. Select the right project (if not already selected)
  5. Paste the prompt
  6. Hit Send
- Verifies each step before moving on; if anything fails, you get a notification with the reason
- Shows a log per task so you can see exactly what happened

## Requirements

- macOS 14+ (Sonoma or later)
- Claude desktop app installed
- Accessibility permission granted to Moonlit

## Setup

1. Open `Moonlit.xcodeproj` in Xcode
2. Set your development team in the target signing settings
3. Build and run (⌘R)
4. The app will prompt you to grant Accessibility permission. Open System Settings → Privacy & Security → Accessibility and toggle Moonlit on
5. Click the moon icon in your menu bar, hit `+`, and schedule a task

## Architecture

```
Moonlit/
├── MoonlitApp.swift          — App entry, MenuBarExtra setup
├── Models/
│   ├── ScheduledTask.swift   — Task model + status + log entries
│   └── TaskStore.swift       — Codable JSON persistence
├── Automation/
│   ├── AXElement.swift       — Swift wrapper around AXUIElement
│   ├── AutomationError.swift — Error types + permission helpers
│   ├── ClaudeAutomator.swift — The script that drives Claude desktop
│   └── Scheduler.swift       — Timer that fires due tasks
└── Views/
    ├── MenuBarView.swift     — Main menu bar UI
    ├── TaskRow.swift         — Single task row
    ├── AddTaskView.swift     — New task form
    └── TaskDetailView.swift  — Per-task log viewer
```

## How the automation works

Claude desktop has a clean native accessibility tree, so we navigate by element role + label rather than screen coordinates. Selectors live in `ClaudeAutomator.swift`:

| Element | Selector |
|---|---|
| Code tab | `AXButton` with description `"Code"` |
| New session | Triggered via ⌘N keyboard shortcut |
| Project picker | `AXPopUpButton` with non-empty title |
| Project menu item | `AXMenuItem` with matching title |
| Prompt input | `AXTextArea` with description `"Prompt"` |
| Send button | `AXButton` with description `"Send"` |

If Claude desktop ships a UI change, update the matchers in `ClaudeAutomator.swift`. The Accessibility Inspector (Xcode → Open Developer Tool → Accessibility Inspector) is the tool for finding new selectors.

## Verification & failure handling

Each step has a wait/verify pass:
- App must launch and become responsive within 10s
- Code tab and prompt input must be findable within 5s
- Project picker menu items must appear within 3s
- After paste, Send button must become enabled within 3s

If any step fails, the task is marked `failed`, a notification fires, and the failure reason is saved to the task log. The UI tries to clean up (Escape × 2) so failures don't leave dangling menus.

## Known limitations (v0.1)

- No recurring tasks
- Project name is a free-text field — must match exactly what Claude desktop shows
- No editing existing tasks (delete + re-add)
- "Open folder…" path for projects not in the recent list is not supported
- macOS must be awake at the scheduled time (no wake-from-sleep)

## v0.2 ideas

- Recurring schedules (daily/weekly)
- Live project list dropdown (read from the AX tree on demand)
- Edit existing tasks
- Screenshot-on-failure for debugging
- Optional per-task selectors (advanced UI)
