import AVFoundation
import SwiftUI
import UIKit

struct QRScannerView: UIViewControllerRepresentable {
    let onCode: (String) -> Bool
    let onUnavailable: () -> Void

    func makeUIViewController(context _: Context) -> QRScannerController {
        let controller = QRScannerController()
        controller.onCode = onCode
        controller.onUnavailable = onUnavailable
        return controller
    }

    func updateUIViewController(_: QRScannerController, context _: Context) {}
}

// @unchecked Sendable: AVCaptureSession may be started and stopped from any queue, and
// Apple recommends doing so off the main thread (startRunning blocks).
private final class ScannerSession: @unchecked Sendable {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "co.sharepad.ipad.scanner")

    func start() {
        queue.async { [session] in session.startRunning() }
    }

    func stop() {
        queue.async { [session] in session.stopRunning() }
    }
}

final class QRScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onCode: ((String) -> Bool)?
    var onUnavailable: (() -> Void)?

    private let scanner = ScannerSession()
    private var preview: AVCaptureVideoPreviewLayer?
    private var rotation: AVCaptureDevice.RotationCoordinator?
    private var hasReported = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        AVCaptureDevice.requestAccess(for: .video) { granted in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if granted, configure() {
                    scanner.start()
                } else {
                    onUnavailable?()
                }
            }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        preview?.frame = view.bounds
        if let rotation, let connection = preview?.connection {
            connection.videoRotationAngle = rotation.videoRotationAngleForHorizonLevelPreview
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        scanner.stop()
    }

    private func configure() -> Bool {
        let session = scanner.session
        guard
            let camera = AVCaptureDevice.default(
                .builtInWideAngleCamera,
                for: .video,
                position: .back
            )
            ?? AVCaptureDevice.default(for: .video),
            let input = try? AVCaptureDeviceInput(device: camera),
            session.canAddInput(input)
        else { return false }
        session.addInput(input)
        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return false }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = view.bounds
        view.layer.addSublayer(preview)
        self.preview = preview
        rotation = AVCaptureDevice.RotationCoordinator(device: camera, previewLayer: preview)
        view.setNeedsLayout()
        return true
    }

    nonisolated func metadataOutput(
        _: AVCaptureMetadataOutput,
        didOutput objects: [AVMetadataObject],
        from _: AVCaptureConnection
    ) {
        let text = objects.lazy
            .compactMap { ($0 as? AVMetadataMachineReadableCodeObject)?.stringValue }
            .first
        guard let text else { return }
        MainActor.assumeIsolated {
            guard !hasReported, onCode?(text) == true else { return }
            hasReported = true
            scanner.stop()
        }
    }
}
