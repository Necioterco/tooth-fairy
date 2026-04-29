import ApplicationServices
import AppKit

/// Thin Swift wrapper around AXUIElement so we can write less ceremony.
/// All functions return optionals — callers must verify and handle nil.
struct AXElement {
    let element: AXUIElement

    init(_ element: AXUIElement) {
        self.element = element
    }

    static func systemWide() -> AXElement {
        AXElement(AXUIElementCreateSystemWide())
    }

    static func application(pid: pid_t) -> AXElement {
        AXElement(AXUIElementCreateApplication(pid))
    }

    // MARK: Attribute access

    func attribute<T>(_ name: String) -> T? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, name as CFString, &value)
        guard result == .success else { return nil }
        return value as? T
    }

    var role: String? { attribute(kAXRoleAttribute) }
    var title: String? { attribute(kAXTitleAttribute) }
    var label: String? { attribute(kAXDescriptionAttribute) }
    var axLabel: String? { attribute("AXLabel") }
    var placeholder: String? { attribute(kAXPlaceholderValueAttribute) }
    var value: String? { attribute(kAXValueAttribute) }
    var enabled: Bool? { attribute(kAXEnabledAttribute) }
    var focused: Bool? { attribute(kAXFocusedAttribute) }
    var expanded: Bool? { attribute(kAXExpandedAttribute) }

    /// Element frame in screen coordinates (origin top-left, +y down — same
    /// space CGEvent mouse posts use).
    var frame: CGRect? {
        var posVal: AnyObject?
        var sizeVal: AnyObject?
        guard
            AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posVal) == .success,
            AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeVal) == .success,
            let posRaw = posVal, let sizeRaw = sizeVal
        else { return nil }
        var point = CGPoint.zero
        var size = CGSize.zero
        // swiftlint:disable:next force_cast
        AXValueGetValue(posRaw as! AXValue, .cgPoint, &point)
        // swiftlint:disable:next force_cast
        AXValueGetValue(sizeRaw as! AXValue, .cgSize, &size)
        return CGRect(origin: point, size: size)
    }

    @discardableResult
    func setAttribute<T: AnyObject>(_ name: String, _ value: T) -> Bool {
        AXUIElementSetAttributeValue(element, name as CFString, value) == .success
    }
    var parent: AXElement? {
        var v: AnyObject?
        let r = AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &v)
        guard r == .success, let raw = v else { return nil }
        // swiftlint:disable:next force_cast
        return AXElement(raw as! AXUIElement)
    }

    /// True if any ancestor has role AXMenuBar — used to skip system/app menu
    /// bar entries when looking for transient popup menus.
    var isInMenuBar: Bool {
        var cur: AXElement? = self.parent
        var hops = 0
        while let p = cur, hops < 30 {
            if p.role == kAXMenuBarRole { return true }
            cur = p.parent
            hops += 1
        }
        return false
    }

    /// Returns true if any label-like attribute equals `text`.
    /// Different toolkits (AppKit, Electron, web) expose accessible names through
    /// different AX attributes, so we check the common ones.
    func hasAccessibleName(_ text: String) -> Bool {
        let candidates: [String?] = [label, title, axLabel]
        return candidates.contains { $0 == text }
    }

    var children: [AXElement] {
        let kids: [AXUIElement]? = attribute(kAXChildrenAttribute)
        return (kids ?? []).map(AXElement.init)
    }

    // MARK: Actions

    @discardableResult
    func performAction(_ action: String) -> Bool {
        AXUIElementPerformAction(element, action as CFString) == .success
    }

    @discardableResult
    func press() -> Bool { performAction(kAXPressAction) }

    @discardableResult
    func showMenu() -> Bool { performAction(kAXShowMenuAction) }

    // MARK: Tree search

    /// Walks the subtree breadth-first. `match` returns true when the element is the target.
    /// `maxDepth` caps recursion. Electron-based apps have deep AX trees — keep generous.
    func first(maxDepth: Int = 60, where match: (AXElement) -> Bool) -> AXElement? {
        var queue: [(AXElement, Int)] = [(self, 0)]
        while !queue.isEmpty {
            let (current, depth) = queue.removeFirst()
            if match(current) { return current }
            if depth < maxDepth {
                for child in current.children {
                    queue.append((child, depth + 1))
                }
            }
        }
        return nil
    }

    /// Collect all matching elements in the subtree (used for diagnostics).
    func all(maxDepth: Int = 60, where match: (AXElement) -> Bool) -> [AXElement] {
        var results: [AXElement] = []
        var queue: [(AXElement, Int)] = [(self, 0)]
        while !queue.isEmpty {
            let (current, depth) = queue.removeFirst()
            if match(current) { results.append(current) }
            if depth < maxDepth {
                for child in current.children {
                    queue.append((child, depth + 1))
                }
            }
        }
        return results
    }

    /// Polls for an element, retrying every `interval` seconds up to `timeout`.
    /// Useful for waiting on UI to settle after an action.
    func waitFor(
        timeout: TimeInterval = 5.0,
        interval: TimeInterval = 0.1,
        match: (AXElement) -> Bool
    ) -> AXElement? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let found = first(where: match) {
                return found
            }
            Thread.sleep(forTimeInterval: interval)
        }
        return nil
    }
}

/// Helpers for finding the Claude desktop application.
enum ClaudeApp {
    static let bundleIdentifier = "com.anthropic.claudefordesktop"

    static func runningApp() -> NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first
    }

    static func launch() throws {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in }
        } else {
            throw AutomationError.appNotFound
        }
    }

    static func activate() {
        runningApp()?.activate()
    }

    /// Returns the AX root for the Claude desktop app, launching it if necessary.
    /// Waits up to `timeout` seconds for the app to become available AND for it
    /// to actually become the frontmost application — otherwise CGEvent
    /// keystrokes posted later would land on whatever app the user was using
    /// before, occasionally triggering Claude's Rewind dialog or random
    /// shortcuts in the previous app.
    static func axRoot(timeout: TimeInterval = 10.0) throws -> AXElement {
        if runningApp() == nil {
            try launch()
        }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let app = runningApp(), app.isFinishedLaunching {
                let pid = app.processIdentifier
                // Try activating up to 3 times, polling for frontmost status
                // between attempts. Heavy apps (Atlas, Chrome) sometimes resist
                // a single activate() call.
                for _ in 0..<3 {
                    activate()
                    if waitUntilFrontmost(pid: pid, timeout: 1.5) {
                        Thread.sleep(forTimeInterval: 0.25) // settle key window
                        return AXElement.application(pid: pid)
                    }
                }
                // Couldn't confirm frontmost — return anyway so caller can try
                // its own recovery. Sleeping a bit gives the OS a last chance.
                Thread.sleep(forTimeInterval: 0.5)
                return AXElement.application(pid: pid)
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
        throw AutomationError.appNotReady
    }

    private static func waitUntilFrontmost(pid: pid_t, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == pid {
                return true
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return false
    }
}
