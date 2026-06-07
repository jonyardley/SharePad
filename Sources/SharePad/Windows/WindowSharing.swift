import AppKit

@MainActor
enum WindowSharing {
    static let shareWindowID = NSUserInterfaceItemIdentifier("SharePad.shareWindow")

    private static var lastWindowCount = 0

    /// Exclude every non-feed window from screen sharing so only the iPad feed is
    /// pickable in a call. A window is shareable (`sharingType` defaults `.readOnly`)
    /// before it becomes key, so two triggers run: `didBecomeKey` (on focus) and a
    /// window-count-growth check on the app update tick — which is silent while idle, so
    /// it doesn't regress idle CPU — to catch a window shown without focus. The observers
    /// use the synchronous `addObserver(forName:queue:.main, using:)` form, NOT an
    /// `AsyncStream` Task hop, so the sweep fires in the same runloop tick the notification
    /// posts — before any share picker re-snapshots the window list. The earlier
    /// AsyncStream form let Sparkle's in-process "Update Available" dialog race in.
    /// Residual gaps: (a) a net-zero close+open within one tick is missed; (b) Sparkle's
    /// Downloader/Installer XPC services and `Updater.app` run in separate processes —
    /// out of `NSApp.windows` reach regardless.
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

    private static func observe(_ name: Notification.Name,
                                _ sweep: @escaping @MainActor () -> Void) {
        // `queue: .main` delivers synchronously on the main runloop in the same tick the
        // notification posts; we're MainActor-isolated so jumping into the actor is sound.
        NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { sweep() }
        }
    }
}
