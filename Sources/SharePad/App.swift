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
        // Menu-bar items render monochrome (template), so signal "armed" with a
        // badged symbol rather than a colour the menu bar strips.
        Image(systemName: model.isLive ? "ipad.landscape.badge.play" : "ipad.landscape")
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    let updater = SparkleUpdater()

    func applicationDidFinishLaunching(_: Notification) {
        // Skip capture/update startup under XCTest so the hosted unit tests stay
        // side-effect-free (no CMIO opt-in / camera prompt during `just test`).
        guard NSClassFromString("XCTestCase") == nil else { return }
        model.start()
        updater.start()
        WindowSharing.startGuarding()
    }
}
