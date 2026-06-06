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
    private(set) var launchAtLoginFailed = false

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

    let thumbnailLayer: AVSampleBufferDisplayLayer

    private let capture: CaptureControlling
    private let monitor: DeviceMonitor
    private let window: ShareWindowControlling
    private let preferences: Preferences
    private let sleep: @Sendable (Duration) async -> Void
    private(set) var currentDeviceID: String?
    private var isReconfiguring = false

    // First launch settles (camera grant + iPad trust) *after* discovery sees the
    // device, so the first start can stall — re-attempt. (specs/first-connect-retry.md)
    private var connectGeneration = 0
    private(set) var retryTask: Task<Void, Never>?

    private static let defaultSize = CGSize(width: 820, height: 1180)
    private static let frameTimeout: TimeInterval = 1.5
    private static let startFrameTimeout: TimeInterval = 3.0
    // Provisional — the iPad trust→ready latency is a hardware datum; tune on device.
    static let firstConnectAttempts = 4
    private static let retryDelay: Duration = .milliseconds(1500)

    convenience init(preferences: Preferences = Preferences()) {
        let controller = CaptureController()
        let window = ShareWindowController(
            previewLayer: controller.previewLayer,
            preferences: preferences
        )
        self.init(
            preferences: preferences,
            capture: controller,
            window: window,
            thumbnailLayer: controller.thumbnailLayer
        )
    }

    init(
        preferences: Preferences,
        capture: CaptureControlling,
        window: ShareWindowControlling,
        thumbnailLayer: AVSampleBufferDisplayLayer,
        sleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }
    ) {
        self.preferences = preferences
        self.capture = capture
        self.window = window
        self.thumbnailLayer = thumbnailLayer
        self.sleep = sleep
        monitor = DeviceMonitor()
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
        do {
            try LaunchAtLogin.setEnabled(enabled)
            launchAtLoginFailed = false
        } catch {
            launchAtLoginFailed = true
        }
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

    func popoverDidAppear() {
        capture.setThumbnailActive(true)
    }

    func popoverDidDisappear() {
        capture.setThumbnailActive(false)
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

    /// A full `start()` reporting `isRunning` isn't proof of frames — a present-but-
    /// stalled device runs with none (frozen preview). Confirm a frame before treating
    /// the device as live; a stall routes into `failed` + Retry, same as a start that
    /// never ran. (#24)
    private func startAndConfirm(deviceID: String) async -> Bool {
        guard await capture.start(deviceID: deviceID) else { return false }
        return await capture.awaitFrame(timeout: Self.startFrameTimeout)
    }

    /// Re-establish the session after a runtime error or wake. `resume()` keeps the
    /// connections (preview included) intact; a full `start` is only the fallback.
    /// One attempt per trigger — no auto-loop.
    func restart() async {
        guard let deviceID = currentDeviceID, !isReconfiguring else { return }
        isReconfiguring = true
        isLive = false
        var running = await capture.resume()
        if running {
            running = await capture.awaitFrame(timeout: Self.frameTimeout)
        }
        if !running {
            running = await startAndConfirm(deviceID: deviceID)
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

    func switchTo(deviceID: String) async {
        guard !isReconfiguring,
              let device = devices.first(where: { $0.id == deviceID }) else { return }
        isReconfiguring = true
        currentDeviceID = device.id
        currentDeviceName = device.name
        let running = await startAndConfirm(deviceID: deviceID)
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

    func reconcile(devices: [CaptureDevice]) async {
        self.devices = devices
        switch resolveDevice(
            devices: devices,
            current: currentDeviceID,
            lastUsed: preferences.lastDeviceID
        ) {
        case .teardown:
            cancelAutoConnect()
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
            await beginAutoConnect(device: device)
        }
    }

    private enum ConnectOutcome { case live, notLive, superseded }

    private func cancelAutoConnect() {
        connectGeneration += 1
        retryTask?.cancel()
        retryTask = nil
    }

    private func beginAutoConnect(device: CaptureDevice) async {
        cancelAutoConnect()
        currentDeviceID = device.id
        currentDeviceName = device.name
        isLive = false
        failed = false
        let generation = connectGeneration
        switch await connectOnce(deviceID: device.id, generation: generation) {
        case .live, .superseded:
            return
        case .notLive:
            retryTask = Task { [self] in
                await retryLoop(deviceID: device.id, generation: generation)
            }
        }
    }

    private func retryLoop(deviceID: String, generation: Int) async {
        for _ in 0 ..< max(0, Self.firstConnectAttempts - 1) {
            await sleep(Self.retryDelay)
            guard generation == connectGeneration,
                  currentDeviceID == deviceID,
                  !isLive,
                  devices.contains(where: { $0.id == deviceID })
            else { return }
            switch await connectOnce(deviceID: deviceID, generation: generation) {
            case .live, .superseded: return
            case .notLive: continue
            }
        }
        guard generation == connectGeneration, !isLive else { return }
        failed = true
        window.hide()
        isWindowVisible = false
    }

    private func connectOnce(deviceID: String, generation: Int) async -> ConnectOutcome {
        // Busy (a manual switch / restart owns the session) → not superseded; let the
        // retry loop re-attempt once it frees, rather than stranding the device.
        guard !isReconfiguring else { return .notLive }
        isReconfiguring = true
        let running = await startAndConfirm(deviceID: deviceID)
        isReconfiguring = false
        guard generation == connectGeneration else { return .superseded }
        if running {
            isLive = true
            failed = false
            preferences.lastDeviceID = deviceID
            if autoShowOnConnect, !isWindowVisible {
                presentWindow()
            }
            return .live
        }
        isLive = false
        return .notLive
    }
}
