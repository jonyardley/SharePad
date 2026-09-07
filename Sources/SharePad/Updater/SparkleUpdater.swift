import Sparkle

@MainActor
final class SparkleUpdater: NSObject, SoftwareUpdating {
    private let reporter: DiagnosticsReporting
    // IUO: self must exist before it can be the controller's delegate; assigned
    // once in init, never nil thereafter.
    private var controller: SPUStandardUpdaterController!

    init(reporter: DiagnosticsReporting = DiagnosticsReporter.shared) {
        self.reporter = reporter
        super.init()
        // self is the updater delegate so a dead feed, failed download or bad
        // signature becomes observable (specs/telemetry.md). Sparkle still owns
        // all user-facing update UI; this only adds a failure signal.
        // startingUpdater: false so allocation is side-effect-free under XCTest;
        // start() runs from applicationDidFinishLaunching, past the test guard.
        controller = SPUStandardUpdaterController(
            startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil
        )
    }

    func start() {
        controller.startUpdater()
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    // Sparkle SUErrors.h codes that are normal outcomes, not failures worth a
    // report: no update available, and the user cancelling / deferring an install.
    nonisolated static func shouldReport(abortErrorCode code: Int) -> Bool {
        let benign: Set = [1001, 4007, 4008]
        return !benign.contains(code)
    }
}

extension SparkleUpdater: SPUUpdaterDelegate {
    nonisolated func updater(_: SPUUpdater, didAbortWithError error: Error) {
        let nsError = error as NSError
        // Only filter Sparkle's own benign codes; an error from any other domain is
        // a real failure worth reporting even if its code happens to collide.
        if nsError.domain == SUSparkleErrorDomain,
           !Self.shouldReport(abortErrorCode: nsError.code) {
            return
        }
        // Sparkle invokes delegate callbacks on the main thread.
        MainActor.assumeIsolated { reporter.report(.updateCheckFailed) }
    }
}
