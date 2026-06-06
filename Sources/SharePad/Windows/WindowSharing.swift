import AppKit

@MainActor
enum WindowSharing {
    static let shareWindowID = NSUserInterfaceItemIdentifier("SharePad.shareWindow")

    private static var lastWindowCount = 0

    /// Exclude every non-feed window from screen sharing so only the iPad feed is
    /// pickable in a call. A window is shareable (`sharingType` defaults `.readOnly`)
    /// before it becomes key, so two triggers run: `didBecomeKey` (on focus) and a
    /// window-count-growth check on the app update tick — which is silent while idle, so
    /// it doesn't regress idle CPU — to catch a window shown without focus. Residual: a
    /// net-zero close+open within one tick is missed; fine, aux windows here are transient.
    static func startGuarding() {
        excludeAuxiliaryWindows()
        lastWindowCount = NSApp.windows.count
        observe(NSWindow.didBecomeKeyNotification) { excludeAuxiliaryWindows() }
        observe(NSApplication.didUpdateNotification) {
            let count = NSApp.windows.count
            guard count != lastWindowCount else { return }
            lastWindowCount = count
            excludeAuxiliaryWindows()
        }
    }

    static func excludeAuxiliaryWindows() {
        for window in NSApp.windows where window.identifier != shareWindowID {
            window.sharingType = .none
        }
    }

    private static func observe(_ name: Notification.Name, _ sweep: @escaping () -> Void) {
        Task {
            for await _ in NotificationCenter.default.notifications(named: name) {
                sweep()
            }
        }
    }
}
