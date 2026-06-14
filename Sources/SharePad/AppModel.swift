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

    /// A one-shot, self-expiring event (not a steady AppState case): the iPad vanished
    /// while its share window was up, so the user — possibly mid-call — lost their share.
    private(set) var shareLostSignal = false

    private(set) var autoShowOnConnect: Bool
    private(set) var keepOnTop: Bool
    private(set) var launchAtLogin: Bool
    private(set) var launchAtLoginFailed = false

    private(set) var entitlement: Entitlement = .trial(daysLeft: EntitlementClock.trialDays)
    private(set) var isTrialOverlayShown = false
    // When set, a post-trial session is counting down to the pause; the watermark
    // and popover render it live. Nil once paused, licensed, or not sharing.
    private(set) var sessionEndsAt: Date?

    var isConnected: Bool {
        currentDeviceName != nil
    }

    var sessionLimitMinutes: Int {
        Int(sessionLimit / 60)
    }

    var isWindowHotkeyActive: Bool {
        windowHotkey != nil
    }

    var state: AppState {
        AppState.reduce(access: access, hasDevice: isConnected, isRunning: isLive, failed: failed)
    }

    private var access: CameraAccess {
        switch permission {
        case .authorized: .granted
        case .denied: .denied
        case .restricted: .restricted
        default: .unknown
        }
    }

    let thumbnailLayer: AVSampleBufferDisplayLayer

    private let capture: CaptureControlling
    private let monitor: DeviceMonitor
    private let window: ShareWindowControlling
    private let preferences: Preferences
    private let sleep: @Sendable (Duration) async -> Void
    private let validator: LicenseValidator
    private let now: () -> Date
    private let sessionLimit: TimeInterval
    private var sessionTimer: Task<Void, Never>?
    // The post-trial pause meters actual sharing: `sessionRemaining` is the budget
    // left for `sessionDeviceID`. The same iPad resumes its remaining time on
    // reconnect (unplug/replug can't reset the gate); a different iPad starts fresh.
    private var sessionRemaining: TimeInterval = 0
    private var sessionDeviceID: String?
    private(set) var currentDeviceID: String?
    private var isReconfiguring = false
    private var windowHotkey: GlobalHotkey?

    // First launch settles (camera grant + iPad trust) *after* discovery sees the
    // device, so the first start can stall — re-attempt. (specs/first-connect-retry.md)
    private var connectGeneration = 0
    private(set) var retryTask: Task<Void, Never>?
    private(set) var shareLostDismissTask: Task<Void, Never>?

    private static let defaultSize = CGSize(width: 820, height: 1180)
    private static let frameTimeout: TimeInterval = 1.5
    private static let startFrameTimeout: TimeInterval = 3.0
    // Provisional — the iPad trust→ready latency is a hardware datum; tune on device.
    static let firstConnectAttempts = 4
    private static let retryDelay: Duration = .milliseconds(1500)
    private static let shareLostDuration: Duration = .seconds(10)

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
        sleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) },
        validator: LicenseValidator = .production,
        now: @escaping () -> Date = Date.init,
        sessionLimit: TimeInterval = 5 * 60
    ) {
        self.preferences = preferences
        self.capture = capture
        self.window = window
        self.thumbnailLayer = thumbnailLayer
        self.sleep = sleep
        self.validator = validator
        self.now = now
        self.sessionLimit = sessionLimit
        sessionRemaining = sessionLimit
        monitor = DeviceMonitor()
        autoShowOnConnect = preferences.autoShowOnConnect
        keepOnTop = preferences.keepOnTop
        launchAtLogin = LaunchAtLogin.isEnabled
        if preferences.firstLaunchDate == nil {
            preferences.firstLaunchDate = now()
        }
        refreshEntitlement()
    }

    func start() {
        CMIO.allowScreenCaptureDevices()
        permission = CameraPermission.status
        window.setKeepOnTop(keepOnTop)
        windowHotkey = GlobalHotkey(
            id: GlobalHotkey.WindowToggle.id,
            keyCode: GlobalHotkey.WindowToggle.keyCode,
            modifiers: GlobalHotkey.WindowToggle.modifiers
        ) { [weak self] in self?.toggleWindow() }
        Task { await beginMonitoring() }
        Task { await observeVideoSize() }
        Task { await observeRestarts() }
        Task { await observeWake() }
    }

    func toggleWindow() {
        if isWindowVisible {
            window.hide()
            isWindowVisible = false
            suspendTrialSession()
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
        refreshEntitlement()
        capture.setThumbnailActive(true)
    }

    func popoverDidDisappear() {
        capture.setThumbnailActive(false)
    }

    func dismissShareLost() {
        shareLostDismissTask?.cancel()
        shareLostDismissTask = nil
        shareLostSignal = false
    }

    /// Raise the lost-share signal and auto-expire it, so a stale banner/badge doesn't
    /// linger after the user has moved on (or replugged). Reconnect/dismiss clear it early.
    private func raiseShareLost() {
        shareLostSignal = true
        shareLostDismissTask?.cancel()
        shareLostDismissTask = Task { [self] in
            await sleep(Self.shareLostDuration)
            guard !Task.isCancelled else { return }
            shareLostSignal = false
            shareLostDismissTask = nil
        }
    }

    private func presentWindow() {
        window.show(size: videoSize ?? Self.defaultSize)
        isWindowVisible = true
        armOrResumeTrialSession()
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
}

/// ── Connection lifecycle: discovery → auto-connect → retry → restart ──
extension AppModel {
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
        // No in-process re-check if access is withheld: macOS terminates the app when
        // its camera TCC grant changes, so a later grant self-heals on relaunch.
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
            suspendTrialSession()
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
            // Capture visibility *before* hide() clears it — a teardown while the share
            // window was up is a lost share worth signalling; an idle unplug is silent.
            let wasSharing = isWindowVisible
            cancelAutoConnect()
            currentDeviceID = nil
            currentDeviceName = nil
            isLive = false
            failed = false
            videoSize = nil
            window.hide()
            isWindowVisible = false
            suspendTrialSession()
            await capture.stop()
            if wasSharing { raiseShareLost() }
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
        // Suspend the prior device's countdown/overlay before connecting. The new
        // device's budget is decided in armOrResumeTrialSession: a different iPad
        // starts fresh, the same one resumes — so this must not reset it here.
        suspendTrialSession()
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
        suspendTrialSession()
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
            dismissShareLost() // a reconnect supersedes a prior lost-share banner
            preferences.lastDeviceID = deviceID
            if autoShowOnConnect, !isWindowVisible {
                presentWindow()
            } else if isWindowVisible {
                // Hot-swap: window stayed up, so presentWindow() is skipped — re-arm the
                // expired-trial gate for the new device's session explicitly.
                armOrResumeTrialSession()
            }
            return .live
        }
        isLive = false
        return .notLive
    }
}

/// ── Licensing: trial entitlement, licence entry, expired-session gate ──
extension AppModel {
    @discardableResult
    func enterLicense(email: String, key: String) -> Bool {
        guard validator.isValid(key: key, email: email) else { return false }
        preferences.licenseEmail = LicenseValidator.normalize(email)
        preferences.licenseKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        refreshEntitlement()
        resetTrialSession()
        return true
    }

    func openBuyPage() {
        guard let url = License.buyURL else { return }
        NSWorkspace.shared.open(url)
    }

    func openRecoverPage() {
        guard let url = License.recoverURL else { return }
        NSWorkspace.shared.open(url)
    }

    func refreshEntitlement() {
        entitlement = EntitlementClock.entitlement(
            firstLaunch: preferences.firstLaunchDate ?? now(),
            now: now(),
            isLicensed: isStoredLicenseValid
        )
    }

    private var isStoredLicenseValid: Bool {
        guard let email = preferences.licenseEmail,
              let key = preferences.licenseKey else { return false }
        return validator.isValid(key: key, email: email)
    }

    private func armOrResumeTrialSession() {
        refreshEntitlement()
        guard entitlement == .trialExpired, sessionTimer == nil,
              !isTrialOverlayShown else { return }
        if currentDeviceID != sessionDeviceID {
            sessionDeviceID = currentDeviceID
            sessionRemaining = sessionLimit
        }
        guard sessionRemaining > 0 else {
            showTrialPause()
            return
        }
        let remaining = sessionRemaining
        let deadline = now().addingTimeInterval(remaining)
        sessionEndsAt = deadline
        window.setTrialCountdown(endsAt: deadline)
        sessionTimer = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: .seconds(remaining))
            } catch {
                return
            }
            guard isWindowVisible, entitlement == .trialExpired else { return }
            sessionRemaining = 0
            showTrialPause()
        }
    }

    private func showTrialPause() {
        sessionTimer = nil
        sessionEndsAt = nil
        window.setTrialCountdown(endsAt: nil)
        isTrialOverlayShown = true
        window.setTrialOverlay(true)
    }

    // Stops the countdown and overlay display but keeps the remaining budget and the
    // device it belongs to, so the same iPad resumes on reconnect (Model A).
    private func suspendTrialSession() {
        sessionTimer?.cancel()
        sessionTimer = nil
        if let deadline = sessionEndsAt {
            sessionRemaining = max(0, deadline.timeIntervalSince(now()))
            sessionEndsAt = nil
            window.setTrialCountdown(endsAt: nil)
        }
        if isTrialOverlayShown {
            isTrialOverlayShown = false
            window.setTrialOverlay(false)
        }
    }

    // A licence makes the gate moot: clear the display and forget the budget entirely.
    private func resetTrialSession() {
        suspendTrialSession()
        sessionRemaining = sessionLimit
        sessionDeviceID = nil
    }
}
