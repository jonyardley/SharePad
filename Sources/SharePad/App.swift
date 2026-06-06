import SwiftUI

@main
struct SharePadApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            PopoverView(updater: delegate.updater)
                .environment(delegate.model)
        } label: {
            StatusItemLabel(model: delegate.model)
        }
        .menuBarExtraStyle(.window)
    }
}

private struct StatusItemLabel: View {
    var model: AppModel

    var body: some View {
        // Menu-bar items render monochrome (template), so signal state with a symbol
        // swap, not a colour the menu bar strips. The transient lost-share alert takes
        // precedence so a closed-popover user still sees the share dropped.
        Image(systemName: symbolName)
    }

    private var symbolName: String {
        if model.shareLostSignal { return "exclamationmark.triangle.fill" }
        return model.isLive ? "ipad.landscape.badge.play" : "ipad.landscape"
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    let updater = SparkleUpdater()

    func applicationDidFinishLaunching(_: Notification) {
        // Skip capture/update startup under XCTest so the hosted unit tests stay
        // side-effect-free (no CMIO opt-in / camera prompt during `just test`). XCTest
        // sets this env var in the host process; checking it keeps test-awareness out
        // of the shipping binary's class lookups.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
        else { return }
        model.start()
        updater.start()
        WindowSharing.startGuarding()
    }
}
