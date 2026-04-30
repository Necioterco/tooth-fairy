import ApplicationServices
import AppKit
import Foundation

/// Drives Claude desktop via Accessibility APIs to start a new session in a
/// specific project and submit a prompt. Each step verifies before proceeding.
@MainActor
final class ClaudeAutomator {
    typealias LogHandler = (LogEntry) -> Void

    /// The full flow. Throws AutomationError on any step failure.
    /// `log` is called for each step so the caller can persist a transcript.
    func runScheduledTask(
        prompt: String,
        projectName: String,
        folderPath: String?,
        autoMode: Bool,
        log: LogHandler
    ) throws {
        guard Accessibility.isGranted else {
            throw AutomationError.accessibilityNotGranted
        }

        log(LogEntry(level: .info, message: "Activating Claude desktop"))
        let app = try ClaudeApp.axRoot()

        log(LogEntry(level: .info, message: "Sanitizing UI state (Escape×2)"))
        sanitizeState()

        // Fast path: "Add another folder" button only renders on the Code tab.
        // If we already see it, skip the tab-switch (the active tab's button
        // sometimes has a different AX role and may trigger our sidebar-toggle
        // fallback unnecessarily — ⌘\ collides with 1Password's legacy
        // shortcut on some setups).
        if app.first(where: { el in
            el.role == kAXButtonRole &&
            (el.label == "Add another folder" || el.title == "Add another folder" || el.axLabel == "Add another folder")
        }) != nil {
            log(LogEntry(level: .info, message: "Already on Code tab"))
        } else {
            log(LogEntry(level: .info, message: "Locating Code tab"))
            let codeTab = try locateCodeTabExpandingSidebarIfNeeded(in: app, log: log)
            log(LogEntry(level: .info, message: "Pressing Code tab"))
            try pressCodeTab(codeTab, in: app, log: log)
        }

        log(LogEntry(level: .info, message: "Triggering New session (⌘N)"))
        sendKeyboardShortcut(key: "n", modifiers: .maskCommand)
        Thread.sleep(forTimeInterval: 0.5)

        log(LogEntry(level: .info, message: "Locating prompt input"))
        let promptInput = try waitForPromptInput(in: app, log: log)

        if let folderPath = folderPath, !folderPath.isEmpty {
            log(LogEntry(level: .info, message: "Locating project picker"))
            let picker = try findProjectPicker(in: app, log: log)
            let currentProject = picker.title ?? ""

            if currentProject == projectName {
                log(LogEntry(level: .info, message: "Project already set to \(projectName), skipping picker"))
            } else {
                log(LogEntry(level: .info, message: "Setting project folder to \(folderPath)"))
                try selectProjectByFolder(path: folderPath, picker: picker, app: app, log: log)
            }
        } else {
            log(LogEntry(level: .warning, message: "No folder path on task — skipping project switch"))
        }

        // Re-query the prompt input. After a project switch the page often
        // re-renders, invalidating our earlier AXUIElement reference.
        log(LogEntry(level: .info, message: "Re-locating prompt input after project switch"))
        let freshInput = try waitForPromptInput(in: app, log: log)

        log(LogEntry(level: .info, message: "Focusing prompt input"))
        try focusPromptInput(freshInput)

        var inputForPaste = freshInput
        if autoMode {
            log(LogEntry(level: .info, message: "Switching to Auto mode (⇧⌘M → 4)"))
            sendKeyboardShortcut(key: "m", modifiers: [.maskCommand, .maskShift])
            Thread.sleep(forTimeInterval: 0.4)
            sendKeyboardShortcut(key: "4", modifiers: [])
            Thread.sleep(forTimeInterval: 0.6)

            // First-time enable shows a confirmation modal: "Enable auto mode?"
            // with an "Enable auto mode" button. Click it if present.
            if let confirmBtn = app.waitFor(timeout: 1.5, match: { el in
                guard el.role == kAXButtonRole else { return false }
                let target = "Enable auto mode"
                return el.title == target
                    || el.label == target
                    || el.axLabel == target
                    || el.value == target
            }) {
                log(LogEntry(level: .info, message: "Confirming auto mode in dialog"))
                if !clickElement(confirmBtn) {
                    _ = confirmBtn.press()
                }
                Thread.sleep(forTimeInterval: 0.6)
            } else {
                log(LogEntry(level: .info, message: "No auto-mode confirmation dialog (already enabled for workspace)"))
            }

            // Modal/menu likely re-rendered the prompt area. Re-locate + re-focus.
            log(LogEntry(level: .info, message: "Re-locating prompt input after auto-mode switch"))
            inputForPaste = try waitForPromptInput(in: app, log: log)
            try focusPromptInput(inputForPaste)
        }

        log(LogEntry(level: .info, message: "Pasting prompt (\(prompt.count) chars)"))
        pastePrompt(prompt)
        Thread.sleep(forTimeInterval: 0.6)

        // Verify the paste actually landed in the prompt input. If the value
        // is empty, focus probably wasn't where we thought — re-focus via
        // hardware click and paste again.
        if (inputForPaste.value ?? "").isEmpty {
            log(LogEntry(level: .warning, message: "Prompt input empty after paste — re-focusing via click and retrying"))
            _ = clickElement(inputForPaste)
            Thread.sleep(forTimeInterval: 0.3)
            pastePrompt(prompt)
            Thread.sleep(forTimeInterval: 0.6)
        }

        // Submit. Try plain Return first (Claude's normal submit binding).
        // If the prompt is still in the input after a brief wait, fall back to
        // ⌘+Return, then to clicking the Send button by mouse. This guards
        // against focus drift and against Return being interpreted as a
        // newline insertion.
        try submitPrompt(prompt: prompt, input: inputForPaste, in: app, log: log)

        // Wipe our prompt off the system pasteboard once Claude has it. We
        // only clear if the pasteboard still matches what we wrote — that
        // way we don't clobber anything the user copied in the meantime.
        Thread.sleep(forTimeInterval: 0.4)
        clearPasteboardIfMatches(prompt)

        log(LogEntry(level: .info, message: "Done"))
    }

    private func submitPrompt(prompt: String, input: AXElement, in app: AXElement, log: LogHandler) throws {
        // Strategy 1: plain Return.
        log(LogEntry(level: .info, message: "Submitting via Return"))
        sendKey(keyCode: 36)
        if waitForInputCleared(input, original: prompt, timeout: 1.5) { return }

        // Strategy 2: ⌘+Return (some Claude builds bind this to send).
        log(LogEntry(level: .warning, message: "Return didn't submit — trying ⌘+Return"))
        // Re-focus first in case focus drifted (e.g. into a side panel).
        _ = clickElement(input)
        Thread.sleep(forTimeInterval: 0.2)
        sendKey(keyCode: 36, modifiers: .maskCommand)
        if waitForInputCleared(input, original: prompt, timeout: 1.5) { return }

        // Strategy 3: click the Send button directly.
        log(LogEntry(level: .warning, message: "⌘+Return didn't submit — clicking Send button"))
        if let sendBtn = app.first(where: { el in
            el.role == kAXButtonRole &&
            (el.label == "Send" || el.title == "Send" || el.axLabel == "Send")
        }) {
            if !clickElement(sendBtn) {
                _ = sendBtn.press()
            }
            if waitForInputCleared(input, original: prompt, timeout: 1.5) { return }
        }

        log(LogEntry(level: .error, message: "Prompt didn't submit — input still contains the original text"))
        throw AutomationError.sendButtonNotFound
    }

    /// Returns true once the prompt input no longer contains the original
    /// text (i.e. submission cleared it). Polls up to `timeout` seconds.
    private func waitForInputCleared(_ input: AXElement, original: String, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let current = input.value ?? ""
            if !current.contains(original) {
                return true
            }
            Thread.sleep(forTimeInterval: 0.15)
        }
        return false
    }

    private func clearPasteboardIfMatches(_ text: String) {
        let pasteboard = NSPasteboard.general
        if pasteboard.string(forType: .string) == text {
            pasteboard.clearContents()
        }
    }

    // MARK: - Steps

    private func sanitizeState() {
        sendKey(keyCode: 53) // Escape
        Thread.sleep(forTimeInterval: 0.1)
        sendKey(keyCode: 53)
        Thread.sleep(forTimeInterval: 0.2)
    }

    private func findCodeTab(in app: AXElement, timeout: TimeInterval = 5.0) -> AXElement? {
        // Match the actual sidebar Code tab. Disambiguate from other buttons
        // named "Code" (e.g. category cards on the Chat landing page) by
        // requiring sibling buttons "Chat" and "Cowork" — the trio that
        // defines the tab group.
        if let tab = app.waitFor(timeout: timeout, match: { el in
            guard el.role == kAXButtonRole else { return false }
            guard nameMatches(el, "Code") else { return false }
            guard let parent = el.parent else { return false }
            let siblingNames = parent.children.flatMap { sib -> [String] in
                [sib.label, sib.title, sib.axLabel].compactMap { $0 }
            }
            return siblingNames.contains("Chat") && siblingNames.contains("Cowork")
        }) {
            return tab
        }

        // Fallback: highest "Code" button in the window (smallest y), which
        // for Claude's layout is the sidebar tab rather than a card.
        let allCode = app.all { el in
            el.role == kAXButtonRole && nameMatches(el, "Code")
        }
        return allCode.min { (a, b) -> Bool in
            (a.frame?.minY ?? .greatestFiniteMagnitude) < (b.frame?.minY ?? .greatestFiniteMagnitude)
        }
    }

    private func nameMatches(_ el: AXElement, _ target: String) -> Bool {
        return el.label == target || el.title == target || el.axLabel == target
    }

    private func frameString(_ f: CGRect) -> String {
        return "(\(Int(f.origin.x)),\(Int(f.origin.y)) \(Int(f.size.width))×\(Int(f.size.height)))"
    }

    /// Clicks the Code tab. AXPress on Electron tab buttons often returns
    /// success without actually switching tabs, so we use a hardware mouse
    /// click. We don't try to "verify" the click here — downstream steps
    /// (prompt input search, project picker) will surface specific errors
    /// if the click didn't land.
    private func pressCodeTab(_ codeTab: AXElement, in app: AXElement, log: LogHandler) throws {
        if !clickElement(codeTab) {
            // No frame available — fall back to AXPress.
            if !codeTab.press() {
                throw AutomationError.codeTabNotFound
            }
        }
        Thread.sleep(forTimeInterval: 0.6)
    }

    /// Looks for the Code tab. If absent (e.g. sidebar fully collapsed), tries
    /// ⌘B to expose it and retries. We avoid ⌘\ because it collides with
    /// 1Password's legacy global shortcut on many setups.
    private func locateCodeTabExpandingSidebarIfNeeded(in app: AXElement, log: LogHandler) throws -> AXElement {
        if let tab = findCodeTab(in: app, timeout: 2.0) { return tab }

        log(LogEntry(level: .info, message: "Code tab missing — toggling sidebar (⌘B)"))
        sendKeyboardShortcut(key: "b", modifiers: .maskCommand)
        Thread.sleep(forTimeInterval: 0.4)
        if let tab = findCodeTab(in: app, timeout: 2.0) { return tab }

        // Restore sidebar to prior state to avoid leaving it in a weird
        // configuration if our toggle didn't help.
        sendKeyboardShortcut(key: "b", modifiers: .maskCommand)
        throw AutomationError.codeTabNotFound
    }

    private func waitForPromptInput(in app: AXElement, log: LogHandler) throws -> AXElement {
        // Code tab's prompt input has accessible name exactly "Prompt".
        // Chat tab's input is "Write your prompt to Claude" — distinct.
        // Matching strictly here lets us catch the case where the Code tab
        // didn't actually switch. Fall back to placeholder presence as a
        // last resort.
        let textRoles: Set<String> = [kAXTextAreaRole, kAXTextFieldRole]
        if let input = app.waitFor(timeout: 8.0, match: { el in
            guard let r = el.role, textRoles.contains(r) else { return false }
            if el.hasAccessibleName("Prompt") { return true }
            return false
        }) {
            return input
        }
        // Secondary pass: loose match if the exact match failed (e.g. Claude
        // renamed the field). This is logged so we know the strict match
        // missed.
        if let input = app.first(where: { el in
            guard let r = el.role, textRoles.contains(r) else { return false }
            let names = [el.label, el.title, el.axLabel].compactMap { $0 }
            return names.contains { $0.range(of: "prompt", options: .caseInsensitive) != nil }
        }) {
            log(LogEntry(level: .warning, message: "Prompt input matched only by loose 'prompt' substring — \(input.label ?? input.title ?? "?")"))
            return input
        }

        // Diagnostic: dump every text-like element we can see so we can tell
        // why the match failed (wrong role, different label attribute, etc.).
        log(LogEntry(level: .info, message: "Prompt input not found — dumping AX text candidates"))
        let candidates = app.all { el in
            guard let r = el.role else { return false }
            return textRoles.contains(r) || r == "AXStaticText" || r == "AXTextGroup"
        }
        if candidates.isEmpty {
            log(LogEntry(level: .error, message: "No AXTextArea/AXTextField/AXStaticText found in tree"))
        } else {
            for (i, el) in candidates.prefix(20).enumerated() {
                let role = el.role ?? "?"
                let title = el.title ?? ""
                let desc = el.label ?? ""
                let axl = el.axLabel ?? ""
                let ph = el.placeholder ?? ""
                let val = (el.value ?? "").prefix(40)
                log(LogEntry(level: .info, message: "[\(i)] role=\(role) title=\"\(title)\" desc=\"\(desc)\" axLabel=\"\(axl)\" placeholder=\"\(ph)\" value=\"\(val)\""))
            }
        }
        throw AutomationError.promptInputNotFound
    }

    /// Titles of non-project popup buttons that share the toolbar with the
    /// project picker. Used to exclude false matches.
    private static let nonProjectPopupTitles: Set<String> = [
        "Local", "Accept edits", "Transcript view mode", "Add",
        "Plan mode", "Auto", "Always", "Never"
    ]
    /// Prefixes for popup titles we know aren't the project picker
    /// (model selector "Opus 4.7 1M · Extra high", usage chip "Usage: plan 50%", etc.).
    private static let nonProjectPopupPrefixes: [String] = [
        "Opus", "Sonnet", "Haiku", "Claude", "Usage"
    ]

    private func findProjectPicker(in app: AXElement, log: LogHandler) throws -> AXElement {
        // Anchor on the "Add another folder" button — only renders on the
        // Code tab and is unique by name.
        let addButton = app.waitFor(timeout: 4.0, match: { el in
            el.role == kAXButtonRole &&
            (el.label == "Add another folder" || el.title == "Add another folder" || el.axLabel == "Add another folder")
        })
        guard let addButton else {
            throw AutomationError.projectPickerNotFound
        }

        // The project picker is the AXPopUpButton that sits visually next to
        // the Add button (same row, just to its left). Use spatial matching
        // because the two are not always in the same AX subtree.
        if let addFrame = addButton.frame {
            let popups = app.all { $0.role == kAXPopUpButtonRole }
            let nearby = popups.filter { pop in
                guard let f = pop.frame else { return false }
                let sameRow = abs(f.midY - addFrame.midY) < 30
                let nearX = abs(f.midX - addFrame.midX) < 250
                return sameRow && nearX
            }
            if let picker = nearby.first(where: { isProjectPicker($0) }) {
                return picker
            }
            // Diagnostic: dump ALL popups in the app with frames so we can see
            // where the project picker actually lives.
            log(LogEntry(level: .info, message: "No qualifying project picker — dumping all popups with frames (Add button at \(frameString(addFrame)))"))
            for (i, p) in popups.prefix(30).enumerated() {
                let title = p.title ?? ""
                let desc = p.label ?? ""
                let axl = p.axLabel ?? ""
                let f = p.frame.map(frameString) ?? "—"
                log(LogEntry(level: .info, message: "[\(i)] frame=\(f) title=\"\(title)\" desc=\"\(desc)\" axLabel=\"\(axl)\""))
            }
        }

        // Fallback: walk up the ancestor chain in case the spatial search
        // missed (e.g. frames not yet computed).
        var anchor: AXElement? = addButton.parent
        var depth = 0
        while let current = anchor, depth < 5 {
            let popups = current.all { $0.role == kAXPopUpButtonRole }
            if let picker = popups.first(where: { isProjectPicker($0) }) {
                return picker
            }
            anchor = current.parent
            depth += 1
        }

        throw AutomationError.projectPickerNotFound
    }

    private func isProjectPicker(_ el: AXElement) -> Bool {
        guard let t = el.title, !t.isEmpty else { return false }
        if Self.nonProjectPopupTitles.contains(t) { return false }
        if Self.nonProjectPopupPrefixes.contains(where: { t.hasPrefix($0) }) { return false }
        return true
    }

    /// Selects the project by clicking the picker's "Open folder…" entry,
    /// which surfaces a native NSOpenPanel. Cmd+Shift+G + paste path + Return
    /// navigates to the folder, then Return again triggers the panel's
    /// default "Open" button. This is far more deterministic than name-
    /// matching dropdown rows in the Electron picker.
    private func selectProjectByFolder(
        path: String,
        picker: AXElement,
        app: AXElement,
        log: LogHandler
    ) throws {
        log(LogEntry(level: .info, message: "Opening project menu"))
        try openPicker(picker, log: log)
        Thread.sleep(forTimeInterval: 0.5)

        // Find the "Open folder…" item in any opened menu container.
        let containerRoles: Set<String> = ["AXList", "AXGroup", "AXScrollArea"]
        guard let menuRoot = findOpenedMenu(in: app, picker: picker, containerRoles: containerRoles) else {
            sendKey(keyCode: 53)
            throw AutomationError.projectPickerNotFound
        }

        let openFolderNames = ["Open folder…", "Open folder...", "Open Folder…", "Open Folder..."]
        let interactiveRoles: Set<String> = [kAXMenuItemRole, kAXButtonRole, kAXRowRole, kAXCellRole]
        var openFolderItem: AXElement? = menuRoot.first(where: { el in
            guard let r = el.role, interactiveRoles.contains(r) else { return false }
            return openFolderNames.contains { name in
                el.hasAccessibleName(name) || el.title == name || el.value == name
            }
        })
        if openFolderItem == nil {
            // Fallback: static text + climb to row.
            if let txt = menuRoot.first(where: { el in
                el.role == kAXStaticTextRole &&
                openFolderNames.contains { n in el.value == n || el.title == n || el.hasAccessibleName(n) }
            }) {
                openFolderItem = clickableAncestor(of: txt) ?? txt
            }
        }
        guard let item = openFolderItem else {
            log(LogEntry(level: .error, message: "Couldn't find 'Open folder…' in dropdown"))
            sendKey(keyCode: 53)
            throw AutomationError.projectNotInList(path)
        }

        log(LogEntry(level: .info, message: "Clicking Open folder…"))
        if !clickElement(item) {
            _ = item.press()
        }
        Thread.sleep(forTimeInterval: 1.2) // NSOpenPanel needs a beat to mount.

        // Cmd+Shift+G — "Go to folder" sheet inside NSOpenPanel.
        log(LogEntry(level: .info, message: "Opening 'Go to folder' (⌘⇧G)"))
        sendKey(keyCode: 5, modifiers: [.maskCommand, .maskShift]) // G
        Thread.sleep(forTimeInterval: 0.4)

        // Paste the path + Return to navigate.
        log(LogEntry(level: .info, message: "Entering folder path"))
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(path, forType: .string)
        Thread.sleep(forTimeInterval: 0.1)
        sendKeyboardShortcut(key: "v", modifiers: .maskCommand)
        Thread.sleep(forTimeInterval: 0.2)
        sendKey(keyCode: 36) // Return — confirm "Go to folder"
        Thread.sleep(forTimeInterval: 0.5)

        // Return again — NSOpenPanel default button is "Open".
        log(LogEntry(level: .info, message: "Confirming Open"))
        sendKey(keyCode: 36)
        Thread.sleep(forTimeInterval: 1.2) // panel close + Claude refocus
    }

    private func selectProject(
        _ name: String,
        picker: AXElement,
        app: AXElement,
        log: LogHandler
    ) throws {
        log(LogEntry(level: .info, message: "Opening project menu"))
        try openPicker(picker, log: log)
        Thread.sleep(forTimeInterval: 0.5)

        // The opened dropdown is a transient AXMenu/AXList that did not exist
        // before the press. Find it freshly each call. Restricting the item
        // search to this subtree avoids false-positive matches on sidebar
        // entries, recent task labels, etc. that share the project name.
        let containerRoles: Set<String> = ["AXList", "AXGroup", "AXScrollArea"]
        guard let menuRoot = findOpenedMenu(in: app, picker: picker, containerRoles: containerRoles) else {
            log(LogEntry(level: .error, message: "Project menu didn't open"))
            sendKey(keyCode: 53)
            throw AutomationError.projectPickerNotFound
        }

        // Prefer interactive container roles first; fall back to static text only
        // if nothing else matches (and we'll try to climb to a clickable parent).
        let interactiveRoles: Set<String> = [
            kAXMenuItemRole, kAXButtonRole, kAXRowRole, kAXCellRole
        ]
        var match: AXElement? = menuRoot.waitFor(timeout: 2.0, match: { el in
            guard let r = el.role, interactiveRoles.contains(r) else { return false }
            return el.hasAccessibleName(name) || el.value == name
        })
        if match == nil {
            // Fall back: AXStaticText with the project name; climb to its row/button.
            if let text = menuRoot.first(where: { el in
                el.role == kAXStaticTextRole &&
                (el.hasAccessibleName(name) || el.value == name || el.title == name)
            }) {
                match = clickableAncestor(of: text) ?? text
            }
        }

        if let menuItem = match {
            log(LogEntry(level: .info, message: "Selecting \(name) from menu"))
            // Mouse click at item's frame center — Electron rows often ignore AXPress.
            if !clickElement(menuItem) {
                // Last resort: AXPress.
                _ = menuItem.press()
            }
            Thread.sleep(forTimeInterval: 0.5)
            // Verify the picker actually changed (poll briefly — title may lag).
            let deadline = Date().addingTimeInterval(2.0)
            while Date() < deadline {
                if (picker.title ?? "") == name { return }
                Thread.sleep(forTimeInterval: 0.1)
            }
            let updated = picker.title ?? ""
            log(LogEntry(level: .error, message: "Picker title still '\(updated)' after selection"))
            throw AutomationError.projectNotInList(name)
        }

        // Diagnostic: dump candidates inside the menu container only.
        log(LogEntry(level: .info, message: "Project menu item '\(name)' not in menu — dumping candidates"))
        let dumpRoles: Set<String> = [
            kAXMenuItemRole, kAXButtonRole, kAXStaticTextRole, kAXRowRole, kAXCellRole
        ]
        let candidates = menuRoot.all { el in
            guard let r = el.role else { return false }
            return dumpRoles.contains(r)
        }
        for (i, el) in candidates.prefix(40).enumerated() {
            let role = el.role ?? "?"
            let title = el.title ?? ""
            let desc = el.label ?? ""
            let axl = el.axLabel ?? ""
            let val = el.value ?? ""
            log(LogEntry(level: .info, message: "[\(i)] role=\(role) title=\"\(title)\" desc=\"\(desc)\" axLabel=\"\(axl)\" value=\"\(val)\""))
        }
        sendKey(keyCode: 53) // Escape menu
        throw AutomationError.projectNotInList(name)
    }

    /// Climbs the parent chain looking for an element whose role is something
    /// the AX system treats as clickable.
    private func clickableAncestor(of el: AXElement) -> AXElement? {
        let roles: Set<String> = [kAXMenuItemRole, kAXButtonRole, kAXRowRole, kAXCellRole]
        var cur: AXElement? = el.parent
        var hops = 0
        while let p = cur, hops < 10 {
            if let r = p.role, roles.contains(r) { return p }
            cur = p.parent
            hops += 1
        }
        return nil
    }

    /// Posts a hardware-level mouse click at the center of the element's frame.
    /// Electron rows reliably respond to this when AXPress is a no-op.
    @discardableResult
    private func clickElement(_ el: AXElement) -> Bool {
        guard let f = el.frame, f.width > 0, f.height > 0 else { return false }
        let center = CGPoint(x: f.midX, y: f.midY)
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return false }
        let down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: center, mouseButton: .left)
        let up = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: center, mouseButton: .left)
        down?.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.03)
        up?.post(tap: .cghidEventTap)
        return true
    }

    /// Opens the project picker. Tries multiple strategies because Electron-
    /// rendered popups don't always honor AXPress.
    private func openPicker(_ picker: AXElement, log: LogHandler) throws {
        // 1. Set AXExpanded = true (preferred — direct AX API).
        if picker.setAttribute(kAXExpandedAttribute, true as CFBoolean) {
            Thread.sleep(forTimeInterval: 0.2)
            if picker.expanded == true { return }
        }
        // 2. AXPress action.
        if picker.press() {
            Thread.sleep(forTimeInterval: 0.2)
            if picker.expanded == true { return }
        }
        // 3. AXShowMenu action.
        if picker.showMenu() {
            Thread.sleep(forTimeInterval: 0.2)
            if picker.expanded == true { return }
        }
        // 4. Last resort: hardware mouse click at picker's frame center. Avoid
        //    Space keypress because Rewind / other system apps register global
        //    Space shortcuts that would intercept it.
        if clickElement(picker) {
            Thread.sleep(forTimeInterval: 0.3)
            if picker.expanded == true { return }
        }

        log(LogEntry(level: .error, message: "Picker did not expand after AXExpanded/press/showMenu/click"))
    }

    /// Finds the dropdown container for the project picker. Order of attempts:
    ///   1. The picker's own subtree (native AXPopUpButtons hang their menu here)
    ///   2. An AXMenu in the app that is NOT inside the AXMenuBar (Apple/app menus)
    ///   3. Any AXList / AXGroup / AXScrollArea outside the menu bar with several
    ///      child rows/buttons (Electron-rendered dropdowns)
    private func findOpenedMenu(in app: AXElement, picker: AXElement, containerRoles: Set<String>) -> AXElement? {
        if let m = picker.first(maxDepth: 6, where: { el in
            guard let r = el.role else { return false }
            return r == kAXMenuRole || containerRoles.contains(r)
        }) {
            return m
        }
        if let m = app.first(where: { el in
            el.role == kAXMenuRole && !el.isInMenuBar
        }) {
            return m
        }
        return app.first { el in
            guard let r = el.role, containerRoles.contains(r) else { return false }
            if el.isInMenuBar { return false }
            let items = el.all(maxDepth: 4) { child in
                guard let cr = child.role else { return false }
                return cr == kAXMenuItemRole || cr == kAXRowRole || cr == kAXButtonRole
            }
            return items.count >= 2
        }
    }

    private func focusPromptInput(_ input: AXElement) throws {
        // Strategy ladder:
        //   1. AXFocused=true (cleanest, fastest)
        //   2. AXPress  (some Electron text areas accept this)
        //   3. Hardware mouse click at the input's frame center (always works)
        // Verify with the AXFocused attribute between attempts.
        if input.setAttribute(kAXFocusedAttribute, true as CFBoolean) {
            Thread.sleep(forTimeInterval: 0.2)
            if input.focused == true { return }
        }
        if input.press() {
            Thread.sleep(forTimeInterval: 0.2)
            if input.focused == true { return }
        }
        if clickElement(input) {
            Thread.sleep(forTimeInterval: 0.3)
            if input.focused == true { return }
            // The AXFocused attribute on Electron text areas sometimes lags or
            // never reports true even when the element is in fact receiving
            // keystrokes. Treat the click as success if the element exists.
            return
        }
        throw AutomationError.promptInputNotFocused
    }

    private func pastePrompt(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        Thread.sleep(forTimeInterval: 0.1)
        sendKeyboardShortcut(key: "v", modifiers: .maskCommand)
    }

    private func waitForEnabledSendButton(in app: AXElement) throws -> AXElement {
        // Re-query each iteration because the disabled state changes.
        let deadline = Date().addingTimeInterval(3.0)
        while Date() < deadline {
            if let btn = app.first(where: { el in
                el.role == kAXButtonRole && el.label == "Send"
            }) {
                if btn.enabled == true {
                    return btn
                }
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        // Final check: did we find the button at all?
        guard let btn = app.first(where: { el in
            el.role == kAXButtonRole && el.label == "Send"
        }) else {
            throw AutomationError.sendButtonNotFound
        }
        if btn.enabled != true {
            throw AutomationError.sendButtonStillDisabled
        }
        return btn
    }

    // MARK: - Keyboard event posting

    private func sendKey(keyCode: CGKeyCode, modifiers: CGEventFlags = []) {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        down?.flags = modifiers
        up?.flags = modifiers
        down?.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.02)
        up?.post(tap: .cghidEventTap)
    }

    private func sendKeyboardShortcut(key: String, modifiers: CGEventFlags) {
        guard let keyCode = KeyMap.code(for: key) else { return }
        sendKey(keyCode: keyCode, modifiers: modifiers)
    }
}

/// Minimal key code map for the keys we need.
enum KeyMap {
    static func code(for char: String) -> CGKeyCode? {
        switch char.lowercased() {
        case "n": return 45
        case "v": return 9
        case "c": return 8
        case "a": return 0
        case "b": return 11
        case "g": return 5
        case "m": return 46
        case "\\": return 42
        case "1": return 18
        case "2": return 19
        case "3": return 20
        case "4": return 21
        default: return nil
        }
    }
}
