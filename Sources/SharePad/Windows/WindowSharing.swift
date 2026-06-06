import AppKit

@MainActor
enum WindowSharing {
    static let shareWindowID = NSUserInterfaceItemIdentifier("SharePad.shareWindow")

    /// Re-exclude every non-feed window whenever one becomes key, so a window opened
    /// mid-call (About panel, Sparkle dialog) can't slip into a call's window picker.
    static func startGuarding() {
        excludeAuxiliaryWindows()
        Task {
            for await _ in NotificationCenter.default.notifications(
                named: NSWindow.didBecomeKeyNotification
            ) {
                excludeAuxiliaryWindows()
            }
        }
    }

    static func excludeAuxiliaryWindows() {
        for window in NSApp.windows where window.identifier != shareWindowID {
            window.sharingType = .none
        }
    }
}
