import AppKit
import AVFoundation
import Observation

@MainActor
@Observable
final class AppModel {
    private(set) var permission: AVAuthorizationStatus = .notDetermined
    private(set) var currentDeviceName: String?
    private(set) var devices: [CaptureDevice] = []
    private(set) var isLive = false
    private(set) var failed = false
    private(set) var videoSize: CGSize?
    private(set) var isWindowVisible = false

    private(set) var autoShowOnConnect: Bool
    private(set) var keepOnTop: Bool
    private(set) var launchAtLogin: Bool

    var isConnected: Bool {
        currentDeviceName != nil
    }

    var state: AppState {
        AppState.reduce(access: access, hasDevice: isConnected, isRunning: isLive, failed: failed)
    }

    private var access: CameraAccess {
        switch permission {
        case .authorized: .granted
        case .denied, .restricted: .denied
        default: .unknown
        }
    }

    private let capture: CaptureControlling
    private let monitor: DeviceMonitor
    private let window: ShareWindowController
    private let preferences: Preferences
    private(set) var currentDeviceID: String?
    private var isReconfiguring = false

    private static let defaultSize = CGSize(width: 820, height: 1180)

    init(preferences: Preferences = Preferences()) {
        let controller = CaptureController()
        capture = controller
        monitor = DeviceMonitor()
        window = ShareWindowController(
            previewLayer: controller.previewLayer,
            preferences: preferences
        )
        self.preferences = preferences
        autoShowOnConnect = preferences.autoShowOnConnect
        keepOnTop = preferences.keepOnTop
        launchAtLogin = LaunchAtLogin.isEnabled
    }

    func start() {
        CMIO.allowScreenCaptureDevices()
        permission = CameraPermission.status
        window.setKeepOnTop(keepOnTop)
        Task { await beginMonitoring() }
        Task { await observeVideoSize() }
        Task { await observeRestarts() }
        Task { await observeWake() }
    }

    func toggleWindow() {
        if isWindowVisible {
            window.hide()
            isWindowVisible = false
        } else if isConnected {
            presentWindow()
        }
    }

    func selectDevice(id: String) {
        guard id != currentDeviceID, devices.contains(where: { $0.id == id }) else { return }
        Task { await switchTo(deviceID: id) }
    }

    func setAutoShow(_ enabled: Bool) {
        autoShowOnConnect = enabled
        preferences.autoShowOnConnect = enabled
    }

    func setKeepOnTop(_ enabled: Bool) {
        keepOnTop = enabled
        preferences.keepOnTop = enabled
        window.setKeepOnTop(enabled)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        try? LaunchAtLogin.setEnabled(enabled)
        launchAtLogin = LaunchAtLogin.isEnabled
    }

    func openCameraSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    func retry() {
        Task { await restart() }
    }

    private func presentWindow() {
        window.show(size: videoSize ?? Self.defaultSize)
        isWindowVisible = true
    }

    private func observeVideoSize() async {
        for await size in capture.videoSizes {
            videoSize = size
            if isWindowVisible {
                window.updateSize(size)
            }
        }
    }

    private func observeRestarts() async {
        for await _ in capture.restarts {
            await restart()
        }
    }

    private func observeWake() async {
        let notifications = NSWorkspace.shared.notificationCenter
            .notifications(named: NSWorkspace.didWakeNotification)
        for await _ in notifications {
            await restart()
        }
    }

    /// Re-establish the session after a runtime error or wake. `resume()` keeps the
    /// connections (preview included) intact; a full `start` is only the fallback.
    /// One attempt per trigger — no auto-loop.
    private func restart() async {
        guard let deviceID = currentDeviceID, !isReconfiguring else { return }
        isReconfiguring = true
        isLive = false
        var running = await capture.resume()
        if !running {
            running = await capture.start(deviceID: deviceID)
        }
        isLive = running
        failed = !running
        isReconfiguring = false
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

    private func switchTo(deviceID: String) async {
        guard !isReconfiguring,
              let device = devices.first(where: { $0.id == deviceID }) else { return }
        isReconfiguring = true
        currentDeviceID = device.id
        currentDeviceName = device.name
        let running = await capture.start(deviceID: deviceID)
        isLive = running
        failed = !running
        if running {
            preferences.lastDeviceID = device.id
        } else {
            window.hide()
            isWindowVisible = false
        }
        isReconfiguring = false
    }

    private func reconcile(devices: [CaptureDevice]) async {
        self.devices = devices
        switch resolveDevice(
            devices: devices,
            current: currentDeviceID,
            lastUsed: preferences.lastDeviceID
        ) {
        case .teardown:
            currentDeviceID = nil
            currentDeviceName = nil
            isLive = false
            failed = false
            videoSize = nil
            window.hide()
            isWindowVisible = false
            await capture.stop()
        case let .keep(device):
            currentDeviceName = device.name
        case let .switchTo(device):
            currentDeviceID = device.id
            currentDeviceName = device.name
            let running = await capture.start(deviceID: device.id)
            isLive = running
            failed = !running
            if running {
                preferences.lastDeviceID = device.id
                if autoShowOnConnect {
                    presentWindow()
                }
            } else {
                window.hide()
                isWindowVisible = false
            }
        }
    }
}
