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
        // Menu-bar items render monochrome (template), so signal state with a glyph swap,
        // not a colour the menu bar strips. A lost share shows no alarm glyph here — the
        // iPad is simply gone, so the idle mark is honest; the popover banner is the notice.
        icon
    }

    private var icon: Image {
        Image(model.isLive ? "MenuBarIconLive" : "MenuBarIcon")
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
