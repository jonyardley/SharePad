import SwiftUI

@main
struct SharePadApp: App {
    var body: some Scene {
        MenuBarExtra("SharePad", systemImage: "ipad.landscape") {
            PopoverView()
        }
        .menuBarExtraStyle(.window)
    }
}
