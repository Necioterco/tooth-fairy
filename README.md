# Tooth Fairy ✨

A macOS menu bar app that schedules prompts to be sent to the Claude desktop app on your Mac at a specific time. Set it up before bed, wake up to completed sessions in your normal Claude history.

## What it does

- Sits in your menu bar
- Lets you schedule a prompt + project folder + time
- At the scheduled time, drives the Claude desktop app via macOS Accessibility APIs to:
  1. Activate Claude desktop
  2. Switch to the Code tab
  3. Open a new session (⌘N)
  4. Open the project folder via the picker's "Open folder…" entry
  5. Optionally switch to Auto mode
  6. Paste the prompt and submit
- Verifies each step before moving on; if anything fails, you get a notification with the reason
- Shows a log per task so you can see exactly what happened

## Requirements

- macOS 14+ (Sonoma or later)
- Claude desktop app installed
- Accessibility permission granted to Tooth Fairy

## Setup

1. Open `Moonlit.xcodeproj` in Xcode (the project file kept its old name to keep Xcode internals stable; the produced app is `ToothFairy.app`)
2. Set your development team in the target signing settings
3. Build and run (⌘R)
4. The app prompts you to grant Accessibility permission. Open System Settings → Privacy & Security → Accessibility and toggle Tooth Fairy on
5. Click the sparkle in your menu bar, hit `+`, and schedule a task

## Architecture

```
Moonlit/                          ← project source folder (kept for Xcode plumbing)
├── MoonlitApp.swift              — App entry, MenuBarExtra setup
├── Models/
│   ├── ScheduledTask.swift       — Task model + status + log entries
│   └── TaskStore.swift           — Codable JSON persistence
├── Automation/
│   ├── AXElement.swift           — Swift wrapper around AXUIElement
│   ├── AutomationError.swift     — Error types + permission helpers
│   ├── ClaudeAutomator.swift     — Drives Claude desktop
│   └── Scheduler.swift           — Timer that fires due tasks
├── Views/
│   ├── MenuBarView.swift         — Main popup
│   ├── TaskRow.swift             — Single task row
│   ├── AddTaskView.swift         — New task form
│   ├── TaskDetailView.swift      — Per-task log viewer
│   └── AboutView.swift           — About screen
└── Assets.xcassets/              — App icon
```

## Build a signed + notarized DMG

```bash
./scripts/build-dmg.sh
```

Outputs `dist/ToothFairy-vX.Y.Z.dmg` and `dist/ToothFairy.dmg` (stable filename). Requires a Developer ID certificate and a `toothfairy-notary` keychain profile — see comments at the top of the script.

## Website

The landing page lives in `docs/`. Deployed to Vercel by pointing the Root Directory at `docs`.
