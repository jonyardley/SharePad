import AVFoundation
@testable import SharePad

/// @unchecked Sendable mirrors the real CaptureController: recording state is read by
/// tests only after the awaited call returns, so there is no concurrent access.
final class FakeCaptureController: CaptureControlling, @unchecked Sendable {
    let videoSizes = AsyncStream<CGSize> { _ in }
    let restarts = AsyncStream<Void> { _ in }

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

    func resume() async -> Bool {
        resumeCount += 1
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

@MainActor
final class FakeShareWindow: ShareWindowControlling {
    private(set) var shownSizes: [CGSize] = []
    private(set) var hideCount = 0
    private(set) var updatedSizes: [CGSize] = []
    private(set) var keepOnTop: Bool?

    func show(size: CGSize) {
        shownSizes.append(size)
    }

    func hide() {
        hideCount += 1
    }

    func updateSize(_ size: CGSize) {
        updatedSizes.append(size)
    }

    func setKeepOnTop(_ enabled: Bool) {
        keepOnTop = enabled
    }
}
