import AVFoundation
@testable import SharePad

/// @unchecked Sendable mirrors the real CaptureController: recording state is read by
/// tests only after the awaited call returns, so there is no concurrent access.
final class FakeCaptureController: CaptureControlling, @unchecked Sendable {
    let videoSizes = AsyncStream<CGSize> { _ in }
    let hostedLayer = CALayer()
    let thumbnailLayer: CALayer = AVSampleBufferDisplayLayer()
    let restarts: AsyncStream<Void>
    private let restartContinuation: AsyncStream<Void>.Continuation

    init() {
        (restarts, restartContinuation) = AsyncStream.makeStream(of: Void.self)
    }

    func sendRestart() {
        restartContinuation.yield()
    }

    var startResult = true
    var resumeResult = true
    var awaitFrameResult = true
    /// Consumed FIFO; falls back to `awaitFrameResult` when empty. Lets a test stage
    /// "resume stalls, then the fallback start confirms" (#24).
    var awaitFrameResults: [Bool] = []
    private(set) var startedDeviceIDs: [String] = []
    private(set) var resumeCount = 0
    private(set) var stopCount = 0
    private(set) var awaitFrameCount = 0
    private(set) var thumbnailActive: Bool?

    func start(deviceID: String) async -> Bool {
        startedDeviceIDs.append(deviceID)
        return startResult
    }

    var holdsResume = false
    private var heldResume: CheckedContinuation<Void, Never>?
    var isResumeHeld: Bool {
        heldResume != nil
    }

    func releaseResume() {
        heldResume?.resume()
        heldResume = nil
    }

    func resume() async -> Bool {
        resumeCount += 1
        if holdsResume {
            await withCheckedContinuation { heldResume = $0 }
        }
        return resumeResult
    }

    func awaitFrame(timeout _: TimeInterval) async -> Bool {
        awaitFrameCount += 1
        return awaitFrameResults.isEmpty ? awaitFrameResult : awaitFrameResults.removeFirst()
    }

    func stop() async {
        stopCount += 1
    }

    func setThumbnailActive(_ active: Bool) {
        thumbnailActive = active
    }
}

/// @unchecked Sendable: driven from the main actor in tests only.
final class FakeWirelessFeed: WirelessFeeding, @unchecked Sendable {
    let hostedLayer = CALayer()
    let thumbnailLayer: CALayer = AVSampleBufferDisplayLayer()
    let videoSizes = AsyncStream<CGSize> { _ in }
    let statuses = AsyncStream<WirelessStatus> { _ in }
    private(set) var thumbnailActive: Bool?
    private(set) var allowWireless: [Bool] = []
    private(set) var pairingOpened = 0
    private(set) var pairingClosed = 0
    private(set) var forgotten: [UUID] = []
    private(set) var hostActive: [Bool] = []

    func setHostActive(_ active: Bool) {
        hostActive.append(active)
    }

    func start() {}

    func setAllowWireless(_ allowed: Bool) {
        allowWireless.append(allowed)
    }

    func openPairing() {
        pairingOpened += 1
    }

    func closePairing() {
        pairingClosed += 1
    }

    func forget(iPad id: UUID) {
        forgotten.append(id)
    }

    func stop() async {}

    func setThumbnailActive(_ active: Bool) {
        thumbnailActive = active
    }

    func awaitFrame(timeout _: TimeInterval) async -> Bool {
        true
    }
}

@MainActor
final class FakeShareWindow: ShareWindowControlling {
    private(set) var shownSizes: [CGSize] = []
    private(set) var hideCount = 0
    private(set) var updatedSizes: [CGSize] = []
    private(set) var keepOnTop: Bool?

    func show(size: CGSize) {
        shownSizes.append(size)
        isShowing = true
    }

    func hide() {
        hideCount += 1
        isShowing = false
    }

    var isShowing = false

    func updateSize(_ size: CGSize) {
        updatedSizes.append(size)
    }

    private(set) var feedLayers: [CALayer] = []

    func setFeedLayer(_ layer: CALayer) {
        feedLayers.append(layer)
    }

    func setKeepOnTop(_ enabled: Bool) {
        keepOnTop = enabled
    }

    private(set) var trialOverlayStates: [Bool] = []

    func setTrialOverlay(_ visible: Bool) {
        trialOverlayStates.append(visible)
    }

    private(set) var trialCountdownDeadlines: [Date?] = []

    func setTrialCountdown(endsAt: Date?) {
        trialCountdownDeadlines.append(endsAt)
    }

    func setTrialActions(onBuy _: (() -> Void)?, onEnterLicense _: @escaping () -> Void) {}
}

/// Records the non-fatal events AppModel emits, and how often the subscription was
/// refreshed. @unchecked Sendable: touched only from the main actor in tests.
final class SpyDiagnosticsReporter: DiagnosticsReporting, @unchecked Sendable {
    private(set) var events: [DiagnosticEvent] = []
    private(set) var refreshCount = 0

    func report(_ event: DiagnosticEvent) {
        events.append(event)
    }

    func refreshSubscription() {
        refreshCount += 1
    }
}
