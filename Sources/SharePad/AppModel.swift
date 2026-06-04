import AppKit
import AVFoundation
import Observation

@MainActor
@Observable
final class AppModel {
    private(set) var permission: AVAuthorizationStatus = .notDetermined
    private(set) var currentDeviceName: String?
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
    private var currentDeviceID: String?
    private var isRestarting = false

    private static let defaultSize = CGSize(width: 820, height: 1180)

    init(preferences: Preferences = Preferences()) {
        let controller = CaptureController()
        capture = controller
        monitor = DeviceMonitor()
        window = ShareWindowController(previewLayer: controller.previewLayer)
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
        guard let deviceID = currentDeviceID, !isRestarting else { return }
        isRestarting = true
        isLive = false
        var running = await capture.resume()
        if !running {
            running = await capture.start(deviceID: deviceID)
        }
        isLive = running
        failed = !running
        isRestarting = false
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
            failed = false
            videoSize = nil
            window.hide()
            isWindowVisible = false
            await capture.stop()
            return
        }
        guard device.id != currentDeviceID else { return }
        currentDeviceID = device.id
        currentDeviceName = device.name
        let running = await capture.start(deviceID: device.id)
        isLive = running
        failed = !running
        if running, autoShowOnConnect {
            presentWindow()
        } else if !running {
            window.hide()
            isWindowVisible = false
        }
    }
}
