import SwiftUI

@main
struct SharePadApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra("SharePad", systemImage: "ipad.landscape") {
            PopoverView()
                .environment(delegate.model)
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()

    func applicationDidFinishLaunching(_: Notification) {
        model.start()
    }
}
