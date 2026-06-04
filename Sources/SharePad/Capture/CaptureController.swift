import AVFoundation

protocol CaptureControlling: Sendable {
    var videoSizes: AsyncStream<CGSize> { get }
    var restarts: AsyncStream<Void> { get }
    func start(deviceID: String) async -> Bool
    func resume() async -> Bool
    func stop() async
}

/// @unchecked Sendable: `session`, `frameListener`, and the output/connection wiring
/// are mutated only on `sessionQueue`; `previewLayer` is an immutable reference
/// (created on main, wired only on `sessionQueue`); the continuations are Sendable
/// and `sessionObservers` is set up once in `init`.
final class CaptureController: CaptureControlling, @unchecked Sendable {
    let previewLayer: AVCaptureVideoPreviewLayer
    let videoSizes: AsyncStream<CGSize>
    let restarts: AsyncStream<Void>

    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.jonyardley.sharepad.session")
    private let sampleQueue = DispatchQueue(label: "com.jonyardley.sharepad.frames")
    private let dataOutput = AVCaptureVideoDataOutput()
    private let sizeContinuation: AsyncStream<CGSize>.Continuation
    private let restartContinuation: AsyncStream<Void>.Continuation
    private var frameListener: FrameSizeListener?
    private var sessionObservers: [NSObjectProtocol] = []

    init() {
        previewLayer = AVCaptureVideoPreviewLayer(sessionWithNoConnection: session)
        previewLayer.videoGravity = .resizeAspect
        (videoSizes, sizeContinuation) = AsyncStream.makeStream(of: CGSize.self)
        (restarts, restartContinuation) = AsyncStream.makeStream(of: Void.self)

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
    /// video-only data output instead — still no audio, so no mic prompt.
    private func wireDimensionOutput(videoPort: AVCaptureInput.Port) {
        guard session.canAddOutput(dataOutput) else { return }
        let listener = FrameSizeListener { [sizeContinuation] size in
            sizeContinuation.yield(size)
        }
        frameListener = listener
        dataOutput.alwaysDiscardsLateVideoFrames = true
        dataOutput.setSampleBufferDelegate(listener, queue: sampleQueue)
        session.addOutputWithNoConnections(dataOutput)
        let connection = AVCaptureConnection(inputPorts: [videoPort], output: dataOutput)
        guard session.canAddConnection(connection) else { return }
        session.addConnection(connection)
    }

    private func teardown() {
        frameListener = nil
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

/// @unchecked Sendable: `lastSize` is read/written only on the data output's
/// serial delegate queue.
private final class FrameSizeListener: NSObject, @unchecked Sendable {
    private var lastSize: CGSize = .zero
    private let onChange: @Sendable (CGSize) -> Void

    init(onChange: @escaping @Sendable (CGSize) -> Void) {
        self.onChange = onChange
    }
}

extension FrameSizeListener: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from _: AVCaptureConnection
    ) {
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer)
        else { return }
        let dimensions = CMVideoFormatDescriptionGetDimensions(formatDescription)
        let size = CGSize(width: Int(dimensions.width), height: Int(dimensions.height))
        guard size.width > 0, size.height > 0, size != lastSize else { return }
        lastSize = size
        onChange(size)
    }
}
