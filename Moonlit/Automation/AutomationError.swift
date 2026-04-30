import ApplicationServices
import AppKit

enum AutomationError: LocalizedError {
    case accessibilityNotGranted
    case appNotFound
    case appNotReady
    case codeTabNotFound
    case newSessionFailed
    case projectPickerNotFound
    case projectNotInList(String)
    case promptInputNotFound
    case promptInputNotFocused
    case sendButtonNotFound
    case sendButtonStillDisabled
    case verificationFailed(String)

    var errorDescription: String? {
        switch self {
        case .accessibilityNotGranted:
            return "Tooth Fairy needs Accessibility permission. Open System Settings → Privacy & Security → Accessibility and enable Tooth Fairy."
        case .appNotFound:
            return "Claude desktop app not installed."
        case .appNotReady:
            return "Claude desktop didn't finish launching in time."
        case .codeTabNotFound:
            return "Couldn't find the Code tab."
        case .newSessionFailed:
            return "Couldn't open a new session."
        case .projectPickerNotFound:
            return "Couldn't find the project picker button."
        case .projectNotInList(let name):
            return "Project \"\(name)\" wasn't in the picker menu."
        case .promptInputNotFound:
            return "Couldn't find the prompt text area."
        case .promptInputNotFocused:
            return "Prompt text area didn't take focus."
        case .sendButtonNotFound:
            return "Couldn't find the Send button."
        case .sendButtonStillDisabled:
            return "Send button stayed disabled — prompt may not have been entered."
        case .verificationFailed(let detail):
            return "Verification failed: \(detail)"
        }
    }
}

enum Accessibility {
    /// Returns true if granted; if not, prompts the user (system sheet).
    @discardableResult
    static func ensurePermission(prompt: Bool = true) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static var isGranted: Bool {
        AXIsProcessTrusted()
    }

    static func openSystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}
