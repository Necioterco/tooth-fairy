import SwiftUI
import AppKit

@main
struct ToothFairyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Settings scene keeps SwiftUI happy with an App that has no
        // foreground windows. The actual menu bar UI is owned by
        // AppDelegate via NSStatusItem + NSPopover so we get right-click
        // support and finer control over the popover lifecycle.
        Settings { EmptyView() }
    }
}

extension Notification.Name {
    /// Posted from AppDelegate when the user picks "About Tooth Fairy" from
    /// the right-click menu, so the popover can navigate to its About screen.
    static let toothFairyNavigateToAbout = Notification.Name("ToothFairy.navigateToAbout")
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private let taskStore = TaskStore()
    private lazy var scheduler = Scheduler(taskStore: taskStore)

    func applicationDidFinishLaunching(_ notification: Notification) {
        // ── Status item ────────────────────────────────────────────────────
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "sparkles",
                accessibilityDescription: "Tooth Fairy"
            )
            button.image?.isTemplate = true
            button.target = self
            button.action = #selector(handleClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        // ── Popover ────────────────────────────────────────────────────────
        popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 440, height: 540)

        let root = MenuBarView()
            .environmentObject(taskStore)
            .environmentObject(scheduler)
        popover.contentViewController = NSHostingController(rootView: root)
    }

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            showContextMenu(from: sender)
        } else {
            togglePopover(sender)
        }
    }

    private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            // Activate so TextField focus doesn't bounce the popover closed
            // immediately on first interaction.
            NSApp.activate(ignoringOtherApps: true)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func showContextMenu(from sender: NSStatusBarButton) {
        let menu = NSMenu()

        let aboutItem = NSMenuItem(
            title: "About Tooth Fairy",
            action: #selector(menuShowAbout),
            keyEquivalent: ""
        )
        aboutItem.target = self
        menu.addItem(aboutItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(
            title: "Quit Tooth Fairy",
            action: #selector(menuQuit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        // Position just below the status item button.
        let location = NSPoint(x: 0, y: sender.bounds.minY - 4)
        menu.popUp(positioning: nil, at: location, in: sender)
    }

    @objc private func menuShowAbout() {
        if !popover.isShown, let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
        NotificationCenter.default.post(name: .toothFairyNavigateToAbout, object: nil)
    }

    @objc private func menuQuit() {
        NSApp.terminate(nil)
    }
}
