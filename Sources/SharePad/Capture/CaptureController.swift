import AVFoundation

protocol CaptureControlling: Sendable {
    var videoSizes: AsyncStream<CGSize> { get }
    var restarts: AsyncStream<Void> { get }
    func start(deviceID: String) async -> Bool
    func resume() async -> Bool
    func stop() async
    func setThumbnailActive(_ active: Bool)
}

/// @unchecked Sendable: `session` and the output/connection wiring are mutated only
/// on `sessionQueue`; `frameListener`'s state is touched only on `sampleQueue`;
/// `previewLayer`, `thumbnailLayer`, and `frameListener` are immutable references
/// (created on main, fed only off-main); the continuations are Sendable and
/// `sessionObservers` is set up once in `init`.
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
    /// unaffected. Hops to the sample queue so the flag is touched where frames arrive.
    func setThumbnailActive(_ active: Bool) {
        sampleQueue.async { [frameListener] in
            frameListener.setActive(active)
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

        wireDimensionOutput(videoPort: videoPort)

        session.commitConfiguration()
        session.startRunning()
        return session.isRunning
    }

    /// The iPad's video dimensions flip on rotation. KVO on the port's
    /// `formatDescription` aborts the app (AVCaptureInputPort raises
    /// valueForUndefinedKey inside its KVO notification), so dimensions come from a
    /// video-only data output instead — still no audio, so no mic prompt. The same
    /// output's frames also feed the popover thumbnail (gated by `setThumbnailActive`).
    private func wireDimensionOutput(videoPort: AVCaptureInput.Port) {
        guard session.canAddOutput(dataOutput) else { return }
        dataOutput.alwaysDiscardsLateVideoFrames = true
        dataOutput.setSampleBufferDelegate(frameListener, queue: sampleQueue)
        session.addOutputWithNoConnections(dataOutput)
        let connection = AVCaptureConnection(inputPorts: [videoPort], output: dataOutput)
        guard session.canAddConnection(connection) else { return }
        session.addConnection(connection)
    }

    private func teardown() {
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

/// @unchecked Sendable: every stored property is read/written only on the data
/// output's serial delegate queue (`setActive` is dispatched onto it too).
private final class FrameOutput: NSObject, @unchecked Sendable {
    private static let minThumbnailInterval = 1.0 / 15.0

    private let renderer: AVSampleBufferVideoRenderer
    private let onChange: @Sendable (CGSize) -> Void
    private var lastSize: CGSize = .zero
    private var active = false
    private var lastRenderedSeconds: Double?

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
