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
        // A symbol swap, not a colour; a lost share shows idle (design-system.md).
        Image(systemName: model.isSharing ? "ipad.landscape.badge.play" : "ipad.landscape")
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    let updater = SparkleUpdater()

    func applicationDidFinishLaunching(_: Notification) {
        // XCTest's env var, not a class lookup, keeps tests out of startup (capture.md).
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
        else { return }
        model.onEnterLicenseRequested = { [weak model] in
            guard let model else { return }
            LicenseWindow.present(model: model)
        }
        model.onWhatsNewRequested = { [weak model] in
            guard let model else { return }
            let pairing = model.isWirelessAvailable ? ModelPairingOffer(model: model) : nil
            WhatsNewWindow.present(model: model, pairing: pairing)
        }
        model.start()
        updater.start()
        // Subscribe to MetricKit only if the user has opted in (specs/telemetry.md);
        // a no-op otherwise. Guarded above so it never runs under XCTest.
        DiagnosticsReporter.shared.refreshSubscription()
        WindowSharing.startGuarding()
    }
}
