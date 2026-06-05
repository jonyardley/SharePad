import AVFoundation

protocol CaptureControlling: Sendable {
    var videoSizes: AsyncStream<CGSize> { get }
    var restarts: AsyncStream<Void> { get }
    func start(deviceID: String) async -> Bool
    func resume() async -> Bool
    func stop() async
    func setThumbnailActive(_ active: Bool)
    func awaitFrame(timeout: TimeInterval) async -> Bool
}

/// @unchecked Sendable: `session` and the output/connection wiring — plus
/// `dataConnection`, `videoPort`, `thumbnailActive`, `confirmingFrame`, and
/// `formatObserver` — are mutated only on `sessionQueue`; `frameListener`'s state is
/// touched only on `sampleQueue`; `previewLayer`, `thumbnailLayer`, and `frameListener`
/// are immutable references (created on main, fed only off-main); the continuations are
/// Sendable and `sessionObservers` is set up once in `init`.
final class CaptureController: CaptureControlling, @unchecked Sendable {
    let previewLayer: AVCaptureVideoPreviewLayer
    let thumbnailLayer: AVSampleBufferDisplayLayer
    let videoSizes: AsyncStream<CGSize>
    let restarts: AsyncStream<Void>

    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.jonyardley.sharepad.session")
    private let sampleQueue = DispatchQueue(label: "com.jonyardley.sharepad.frames")
    private let dataOutput = AVCaptureVideoDataOutput()
    private let sizeContinuation: AsyncStream<CGSize>.Continuation
    private let restartContinuation: AsyncStream<Void>.Continuation
    private let frameListener: FrameOutput
    private var sessionObservers: [NSObjectProtocol] = []

    // The data output is costly at full rate, so it's *attached* only while the popover
    // thumbnail shows or a frame is being confirmed (#23) — merely disabling the
    // connection doesn't stop the cost. Rotation still works detached via `formatObserver`.
    private var dataConnection: AVCaptureConnection?
    private var videoPort: AVCaptureInput.Port?
    private var thumbnailActive = false
    private var confirmingFrame = false
    private var formatObserver: NSObjectProtocol?

    init() {
        previewLayer = AVCaptureVideoPreviewLayer(sessionWithNoConnection: session)
        previewLayer.videoGravity = .resizeAspect
        let thumbnailLayer = AVSampleBufferDisplayLayer()
        thumbnailLayer.videoGravity = .resizeAspect
        self.thumbnailLayer = thumbnailLayer
        (videoSizes, sizeContinuation) = AsyncStream.makeStream(of: CGSize.self)
        (restarts, restartContinuation) = AsyncStream.makeStream(of: Void.self)
        let renderer = thumbnailLayer.sampleBufferRenderer
        frameListener = FrameOutput(renderer: renderer) { [sizeContinuation] size in
            sizeContinuation.yield(size)
        }

        // Sleep/wake and session hiccups surface as runtime errors / interruption
        // ends; ask AppModel (which owns the current device) to re-establish.
        let onEvent: @Sendable (Notification) -> Void = { [restartContinuation] _ in
            restartContinuation.yield()
        }
        let center = NotificationCenter.default
        sessionObservers = [
            AVCaptureSession.runtimeErrorNotification,
            AVCaptureSession.interruptionEndedNotification,
        ].map { center.addObserver(forName: $0, object: session, queue: nil, using: onEvent) }
    }

    deinit {
        sessionObservers.forEach(NotificationCenter.default.removeObserver)
        if let formatObserver { NotificationCenter.default.removeObserver(formatObserver) }
    }

    func start(deviceID: String) async -> Bool {
        await withCheckedContinuation { continuation in
            sessionQueue.async { [self] in
                continuation.resume(returning: configureAndRun(deviceID: deviceID))
            }
        }
    }

    func stop() async {
        await withCheckedContinuation { continuation in
            sessionQueue.async { [self] in
                if session.isRunning { session.stopRunning() }
                session.beginConfiguration()
                teardown()
                session.commitConfiguration()
                continuation.resume()
            }
        }
    }

    /// Wake/runtime recovery: kick the run loop while keeping connections intact, so
    /// the preview layer resumes. A full teardown re-adds the preview-layer connection,
    /// which leaves the layer frozen on its last frame — so never do that here.
    func resume() async -> Bool {
        await withCheckedContinuation { continuation in
            sessionQueue.async { [self] in
                session.stopRunning()
                session.startRunning()
                continuation.resume(returning: session.isRunning)
            }
        }
    }

    /// Gate the popover thumbnail's frame fan-out — the window's preview connection is
    /// unaffected. Flips the render gate on the sample queue, and attaches/detaches the
    /// data output on the session queue so it isn't producing frames at all while the
    /// popover is closed (#23).
    func setThumbnailActive(_ active: Bool) {
        sampleQueue.async { [frameListener] in
            frameListener.setActive(active)
        }
        sessionQueue.async { [self] in
            thumbnailActive = active
            applyDataOutputAttached()
        }
    }

    /// Confirm frames are actually flowing: `resume()`/`start()` reporting `isRunning`
    /// isn't enough — a stalled device can be "running" with no frames (frozen preview)
    /// (#13, #24). The data output may be detached (popover closed, #23), so attach it
    /// for the confirmation window, then restore.
    func awaitFrame(timeout: TimeInterval) async -> Bool {
        await setConfirmingFrame(true)
        let got = await withCheckedContinuation { continuation in
            sampleQueue.async { [frameListener, sampleQueue] in
                let wait = FrameWait(continuation)
                frameListener.setFrameWaiter { _ = wait.resolve(true) }
                sampleQueue.asyncAfter(deadline: .now() + timeout) {
                    if wait.resolve(false) { frameListener.setFrameWaiter(nil) }
                }
            }
        }
        await setConfirmingFrame(false)
        return got
    }

    private func setConfirmingFrame(_ confirming: Bool) async {
        await withCheckedContinuation { continuation in
            sessionQueue.async { [self] in
                confirmingFrame = confirming
                applyDataOutputAttached()
                continuation.resume()
            }
        }
    }

    /// Add or remove the data output + its connection to match the desired gate. Removing
    /// (not just disabling) is what actually stops the frame-rate cost (#23). Runs only on
    /// `sessionQueue`; wraps its own configuration transaction.
    private func applyDataOutputAttached() {
        let want = thumbnailActive || confirmingFrame
        if want, dataConnection == nil, let videoPort, session.canAddOutput(dataOutput) {
            session.beginConfiguration()
            dataOutput.alwaysDiscardsLateVideoFrames = true
            dataOutput.setSampleBufferDelegate(frameListener, queue: sampleQueue)
            session.addOutputWithNoConnections(dataOutput)
            let connection = AVCaptureConnection(inputPorts: [videoPort], output: dataOutput)
            if session.canAddConnection(connection) {
                session.addConnection(connection)
                dataConnection = connection
            }
            session.commitConfiguration()
        } else if !want, let connection = dataConnection {
            session.beginConfiguration()
            session.removeConnection(connection)
            session.removeOutput(dataOutput)
            dataConnection = nil
            session.commitConfiguration()
        }
    }

    private func configureAndRun(deviceID: String) -> Bool {
        guard let device = AVCaptureDevice(uniqueID: deviceID),
              let input = try? AVCaptureDeviceInput(device: device)
        else { return false }

        session.beginConfiguration()
        teardown()

        // Muxed input carries audio too; add it with no connections and wire only
        // the video port, so macOS never raises a Microphone prompt. (DESIGN.md §6.5)
        guard session.canAddInput(input) else {
            session.commitConfiguration()
            return false
        }
        session.addInputWithNoConnections(input)

        guard let videoPort = input.ports.first(where: { $0.mediaType == .video }) else {
            session.commitConfiguration()
            return false
        }

        let previewConnection = AVCaptureConnection(
            inputPort: videoPort,
            videoPreviewLayer: previewLayer
        )
        guard session.canAddConnection(previewConnection) else {
            session.commitConfiguration()
            return false
        }
        session.addConnection(previewConnection)

        observePortFormat(videoPort: videoPort)
        self.videoPort = videoPort

        session.commitConfiguration()
        applyDataOutputAttached()
        session.startRunning()
        return session.isRunning
    }

    /// The iPad's video dimensions flip on rotation. KVO on the port's
    /// `formatDescription` aborts the app (AVCaptureInputPort raises
    /// valueForUndefinedKey inside its KVO notification), but the matching *notification*
    /// is safe: observe it and read `formatDescription` directly. This keeps rotation
    /// working even while the data output is gated off (popover closed, #23).
    private func observePortFormat(videoPort: AVCaptureInput.Port) {
        formatObserver = NotificationCenter.default.addObserver(
            forName: AVCaptureInput.Port.formatDescriptionDidChangeNotification,
            object: videoPort,
            queue: nil
        ) { [sizeContinuation] notification in
            guard let port = notification.object as? AVCaptureInput.Port,
                  let format = port.formatDescription else { return }
            let dimensions = CMVideoFormatDescriptionGetDimensions(format)
            let size = CGSize(width: Int(dimensions.width), height: Int(dimensions.height))
            if size.width > 0, size.height > 0 {
                sizeContinuation.yield(size)
            }
        }
    }

    private func teardown() {
        if let formatObserver {
            NotificationCenter.default.removeObserver(formatObserver)
            self.formatObserver = nil
        }
        dataConnection = nil
        videoPort = nil
        for connection in session.connections {
            session.removeConnection(connection)
        }
        for output in session.outputs {
            session.removeOutput(output)
        }
        for input in session.inputs {
            session.removeInput(input)
        }
    }
}

/// Resolves an `awaitFrame` continuation exactly once; touched only on the sample queue.
private final class FrameWait: @unchecked Sendable {
    private var continuation: CheckedContinuation<Bool, Never>?

    init(_ continuation: CheckedContinuation<Bool, Never>) {
        self.continuation = continuation
    }

    func resolve(_ value: Bool) -> Bool {
        guard let continuation else { return false }
        self.continuation = nil
        continuation.resume(returning: value)
        return true
    }
}

/// @unchecked Sendable: every stored property is read/written only on the data output's
/// serial delegate queue (`setActive`/`setFrameWaiter` are dispatched onto it too).
private final class FrameOutput: NSObject, @unchecked Sendable {
    private static let minThumbnailInterval = 1.0 / 15.0

    private let renderer: AVSampleBufferVideoRenderer
    private let onChange: @Sendable (CGSize) -> Void
    private var lastSize: CGSize = .zero
    private var active = false
    private var lastRenderedSeconds: Double?
    private var onNextFrame: (@Sendable () -> Void)?

    init(renderer: AVSampleBufferVideoRenderer,
         onChange: @escaping @Sendable (CGSize) -> Void) {
        self.renderer = renderer
        self.onChange = onChange
    }

    func setActive(_ active: Bool) {
        self.active = active
        if !active {
            lastRenderedSeconds = nil
            renderer.flush()
        }
    }

    func setFrameWaiter(_ waiter: (@Sendable () -> Void)?) {
        onNextFrame = waiter
    }
}

extension FrameOutput: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from _: AVCaptureConnection
    ) {
        if let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) {
            let dimensions = CMVideoFormatDescriptionGetDimensions(formatDescription)
            let size = CGSize(width: Int(dimensions.width), height: Int(dimensions.height))
            if size.width > 0, size.height > 0, size != lastSize {
                lastSize = size
                onChange(size)
            }
        }

        // Before the active-gate: the resume() watchdog (#13) needs *any* frame, not
        // only popover-open ones.
        if let onNextFrame {
            self.onNextFrame = nil
            onNextFrame()
        }

        guard active else { return }
        let seconds = sampleBuffer.presentationTimeStamp.seconds
        guard seconds.isFinite,
              shouldRenderFrame(currentSeconds: seconds,
                                lastRenderedSeconds: lastRenderedSeconds,
                                minInterval: Self.minThumbnailInterval),
              renderer.isReadyForMoreMediaData
        else { return }
        renderer.enqueue(sampleBuffer)
        lastRenderedSeconds = seconds
    }
}
