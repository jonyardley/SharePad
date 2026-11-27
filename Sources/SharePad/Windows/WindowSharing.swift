import AppKit

@MainActor
enum WindowSharing {
    static let shareWindowID = NSUserInterfaceItemIdentifier("SharePad.shareWindow")

    private static var lastWindowCount = 0

    // Synchronous, not an AsyncStream hop, so no picker sees an unswept window (capture.md).
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
        for window in NSApp.windows where excludesFromSharing(window.identifier) {
            window.sharingType = .none
        }
    }

    /// Pure so the feed-vs-auxiliary partition is testable without `NSApp.windows`.
    static func excludesFromSharing(_ identifier: NSUserInterfaceItemIdentifier?) -> Bool {
        identifier != shareWindowID
    }

    private static func observe(_ name: Notification.Name,
                                _ sweep: @escaping @MainActor () -> Void) {
        // `queue: .main` delivers synchronously on the main runloop in the same tick the
        // notification posts; we're MainActor-isolated so jumping into the actor is sound.
        NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { sweep() }
        }
    }
}
