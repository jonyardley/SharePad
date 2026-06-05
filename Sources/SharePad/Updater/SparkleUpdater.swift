import Sparkle

@MainActor
final class SparkleUpdater: SoftwareUpdating {
    private let controller: SPUStandardUpdaterController

    init() {
        // startingUpdater: false so allocation is side-effect-free under XCTest;
        // start() is called from applicationDidFinishLaunching, past the test guard.
        controller = SPUStandardUpdaterController(
            startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil
        )
    }

    func start() {
        controller.startUpdater()
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
