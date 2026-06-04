import AVFoundation

protocol CaptureControlling: Sendable {
    func start(deviceID: String) async -> Bool
    func stop() async
}

/// @unchecked Sendable: all AVCaptureSession state is confined to `sessionQueue`;
/// `previewLayer` is created and configured once at init on the main thread.
final class CaptureController: CaptureControlling, @unchecked Sendable {
    let previewLayer: AVCaptureVideoPreviewLayer
    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.jonyardley.sharepad.session")

    init() {
        previewLayer = AVCaptureVideoPreviewLayer(sessionWithNoConnection: session)
        previewLayer.videoGravity = .resizeAspect
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
                clearInputsAndConnections()
                session.commitConfiguration()
                continuation.resume()
            }
        }
    }

    private func configureAndRun(deviceID: String) -> Bool {
        guard let device = AVCaptureDevice(uniqueID: deviceID),
              let input = try? AVCaptureDeviceInput(device: device)
        else { return false }

        session.beginConfiguration()
        clearInputsAndConnections()

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

        let connection = AVCaptureConnection(inputPort: videoPort, videoPreviewLayer: previewLayer)
        guard session.canAddConnection(connection) else {
            session.commitConfiguration()
            return false
        }
        session.addConnection(connection)
        session.commitConfiguration()

        session.startRunning()
        return session.isRunning
    }

    private func clearInputsAndConnections() {
        for connection in session.connections {
            session.removeConnection(connection)
        }
        for input in session.inputs {
            session.removeInput(input)
        }
    }
}
