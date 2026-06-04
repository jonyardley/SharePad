import AVFoundation
import Observation

@MainActor
@Observable
final class AppModel {
    private(set) var permission: AVAuthorizationStatus = .notDetermined
    private(set) var currentDeviceName: String?
    private(set) var isLive = false
    private(set) var videoSize: CGSize?

    private let capture: CaptureControlling
    private let monitor: DeviceMonitor
    private let window: ShareWindowController
    private var currentDeviceID: String?

    private static let defaultSize = CGSize(width: 820, height: 1180)

    init() {
        let controller = CaptureController()
        capture = controller
        monitor = DeviceMonitor()
        window = ShareWindowController(previewLayer: controller.previewLayer)
    }

    func start() {
        CMIO.allowScreenCaptureDevices()
        permission = CameraPermission.status
        Task { await beginMonitoring() }
        Task { await observeVideoSize() }
    }

    private func observeVideoSize() async {
        for await size in capture.videoSizes {
            videoSize = size
            if isLive {
                window.present(size: size)
            }
        }
    }

    private func beginMonitoring() async {
        if permission == .notDetermined {
            _ = await CameraPermission.request()
            permission = CameraPermission.status
        }
        guard permission == .authorized else { return }
        monitor.start()
        for await devices in monitor.devices {
            await reconcile(devices: devices)
        }
    }

    private func reconcile(devices: [CaptureDevice]) async {
        guard let device = devices.first else {
            currentDeviceID = nil
            currentDeviceName = nil
            isLive = false
            videoSize = nil
            window.hide()
            await capture.stop()
            return
        }
        guard device.id != currentDeviceID else { return }
        currentDeviceID = device.id
        currentDeviceName = device.name
        let running = await capture.start(deviceID: device.id)
        isLive = running
        if running {
            window.present(size: videoSize ?? Self.defaultSize)
        } else {
            window.hide()
        }
    }
}
