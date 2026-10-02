import AppKit
import AVFoundation
import Observation
import os

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
    private(set) var wirelessStatus = WirelessStatus()
    private(set) var preferredFeed: FeedKind?
    // The feed whose layer the share window hosts. It only moves when another feed
    // becomes the active one, so a feed that goes away leaves its last frame up.
    private(set) var hostedFeed: FeedKind = .usb
    private var wirelessVideoSize: CGSize?
    private var autoShownPeerID: UUID?

    /// A one-shot, self-expiring event (not a steady AppState case): the iPad vanished
    /// while its share window was up, so the user — possibly mid-call — lost their share.
    private(set) var shareLostSignal = false

    private(set) var autoShowOnConnect: Bool
    private(set) var keepOnTop: Bool
    private(set) var launchAtLogin: Bool
    private(set) var launchAtLoginFailed = false
    private(set) var diagnosticsEnabled: Bool

    private(set) var entitlement: Entitlement = .trial(daysLeft: EntitlementClock.trialDays)
    private(set) var isTrialOverlayShown = false

    /// Set by the composition root (App.swift) so the trial-pause overlay can open
    /// licence entry without the model layer reaching into the UI (LicenseWindow).
    var onEnterLicenseRequested: (() -> Void)?
    var onWhatsNewRequested: (() -> Void)?
    private(set) var isWhatsNewDue = false
    // When set, a post-trial session is counting down to the pause; the watermark
    // and popover render it live. Nil once paused, licensed, or not sharing.
    private(set) var sessionEndsAt: Date?

    var isConnected: Bool {
        currentDeviceName != nil || wirelessStatus.peer != nil
    }

    var sessionLimitMinutes: Int {
        Int(sessionLimit / 60)
    }

    var isWindowHotkeyActive: Bool {
        windowHotkey != nil
    }

    var state: AppState {
        AppState.reduce(
            camera: access,
            usb: usbInput,
            wireless: wirelessStatus.input,
            localNetwork: wirelessStatus.localNetwork,
            preferred: preferredFeed
        )
    }

    private var access: CameraAccess {
        switch permission {
        case .authorized: .granted
        case .denied: .denied
        case .restricted: .restricted
        default: .unknown
        }
    }

    private let capture: CaptureControlling
    private let wireless: WirelessFeeding?
    private let monitor: DeviceMonitor
    private let window: ShareWindowControlling
    private let preferences: Preferences
    private let reporter: DiagnosticsReporting
    private let sleep: @Sendable (Duration) async -> Void
    private let validator: LicenseValidator
    private let now: () -> Date
    private let sessionLimit: TimeInterval
    private let appVersion: String?
    private let featureReleases: [String]
    private let isFreshInstall: Bool
    private var sessionTimer: Task<Void, Never>?
    // The post-trial pause meters actual sharing per iPad: `sessionBudgets[deviceID]`
    // is the time left for that device. The same iPad resumes its remaining time on
    // reconnect or device-switch; a different iPad starts fresh. Keyed per device so
    // alternating between two iPads can't reset either one's budget.
    private var sessionBudgets: [String: TimeInterval] = [:]
    // The device the currently-armed timer/countdown belongs to. Distinct from
    // `currentDeviceID`, which `switchTo` updates to the new device before suspending
    // the old session — so the budget write-back must target the *active* device.
    private var activeSessionDeviceID: String?
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
            wireless: Self.debugWirelessSource(),
            window: window,
            reporter: DiagnosticsReporter.shared,
            sessionLimit: Self.debugSessionLimitOverride ?? 5 * 60,
            featureReleases: WhatsNew.featureReleases + Self.debugFeatureReleases
        )
    }

    #if DEBUG
        // `SHAREPAD_SESSION_LIMIT_SECONDS=10 just run` shortens the post-trial pause budget
        // so the gate is testable without the real 5-minute wait. DEBUG only — the shipping
        // binary always uses the production 5 minutes.
        private static var debugSessionLimitOverride: TimeInterval? {
            ProcessInfo.processInfo.environment["SHAREPAD_SESSION_LIMIT_SECONDS"]
                .flatMap(TimeInterval.init)
        }
    #else
        private static let debugSessionLimitOverride: TimeInterval? = nil
    #endif

    init(
        preferences: Preferences,
        capture: CaptureControlling,
        wireless: WirelessFeeding? = nil,
        window: ShareWindowControlling,
        sleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) },
        validator: LicenseValidator = .production,
        reporter: DiagnosticsReporting = .disabled,
        now: @escaping () -> Date = Date.init,
        sessionLimit: TimeInterval = 5 * 60,
        appVersion: String? = AppModel.bundleVersion,
        featureReleases: [String] = WhatsNew.featureReleases
    ) {
        self.preferences = preferences
        self.capture = capture
        self.wireless = wireless
        self.window = window
        self.sleep = sleep
        self.validator = validator
        self.reporter = reporter
        self.now = now
        self.sessionLimit = sessionLimit
        self.appVersion = appVersion
        self.featureReleases = featureReleases
        isFreshInstall = preferences.firstLaunchDate == nil
        monitor = DeviceMonitor()
        autoShowOnConnect = preferences.autoShowOnConnect
        keepOnTop = preferences.keepOnTop
        diagnosticsEnabled = preferences.diagnosticsEnabled
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
        window.setTrialActions(
            onBuy: License.buyURL != nil ? { [weak self] in self?.openBuyPage() } : nil,
            onEnterLicense: { [weak self] in self?.onEnterLicenseRequested?() }
        )
        windowHotkey = GlobalHotkey(
            id: GlobalHotkey.WindowToggle.id,
            keyCode: GlobalHotkey.WindowToggle.keyCode,
            modifiers: GlobalHotkey.WindowToggle.modifiers
        ) { [weak self] in self?.toggleWindow() }
        Task { await beginMonitoring() }
        Task { await observeVideoSize() }
        Task { await observeRestarts() }
        Task { await observeWake() }
        Task { await checkWhatsNew() }
        if let wireless {
            wireless.start()
            Task { await observeWireless(wireless) }
            Task { await observeWirelessSizes(wireless) }
        }
    }

    func toggleWindow() {
        if isWindowVisible {
            window.hide()
            setWindowVisible(false, "toggle")
            suspendTrialSession()
            presentWhatsNewIfDue()
        } else if isConnected {
            presentWindow()
        }
    }

    func selectDevice(id: String) {
        if preferredFeed == .wireless {
            preferredFeed = .usb
            syncHostedFeed()
        }
        guard id != currentDeviceID, devices.contains(where: { $0.id == id }) else { return }
        Task { await switchTo(deviceID: id) }
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
        wireless?.setThumbnailActive(true)
    }

    func popoverDidDisappear() {
        capture.setThumbnailActive(false)
        wireless?.setThumbnailActive(false)
    }

    func dismissShareLost() {
        shareLostDismissTask?.cancel()
        shareLostDismissTask = nil
        shareLostSignal = false
        presentWhatsNewIfDue()
    }

    /// Raise the lost-share signal and auto-expire it, so a stale popover banner doesn't
    /// linger after the user has moved on (or replugged). Reconnect/dismiss clear it early.
    private func raiseShareLost() {
        reporter.report(.shareLost)
        shareLostSignal = true
        shareLostDismissTask?.cancel()
        shareLostDismissTask = Task { [self] in
            await sleep(Self.shareLostDuration)
            guard !Task.isCancelled else { return }
            shareLostSignal = false
            shareLostDismissTask = nil
            presentWhatsNewIfDue()
        }
    }

    private func presentWindow() {
        window.show(size: hostedVideoSize ?? Self.defaultSize)
        setWindowVisible(true, "present")
        armOrResumeTrialSession()
    }

    private func observeVideoSize() async {
        for await size in capture.videoSizes {
            videoSize = size
            if isWindowVisible, hostedFeed == .usb {
                window.updateSize(size)
            }
        }
    }

    func observeRestarts() async {
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
    // Long enough for an iPad plugged in across an update's relaunch to connect and
    // auto-show, so what's new sees the share window and waits.
    private static let whatsNewSettle: Duration = .seconds(10)

    static var bundleVersion: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    #if DEBUG
        private static var debugFeatureReleases: [String] {
            ProcessInfo.processInfo.environment["SHAREPAD_FEATURE_RELEASE"].map { [$0] } ?? []
        }
    #else
        private static let debugFeatureReleases: [String] = []
    #endif

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
        if !running { reporter.report(.restartFailed) }
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
            // A manual switch is a different iPad: suspend the old device's countdown
            // and re-arm so the gate re-buckets to a fresh budget for the new one.
            suspendTrialSession()
            armOrResumeTrialSession()
        } else {
            hideIfShowingUSB()
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
            let usbWasShown = hideIfShowingUSB()
            await capture.stop()
            if wasSharing, usbWasShown { raiseShareLost() }
        case let .keep(device):
            currentDeviceName = device.name
        case let .switchTo(device):
            await beginAutoConnect(device: device)
        }
        syncHostedFeed()
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
        if hostedFeed == .usb { suspendTrialSession() }
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
        reporter.report(.retryExhausted)
        hideIfShowingUSB()
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
            syncHostedFeed()
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
    func enterLicense(email: String, key: String) -> LicenseCheck {
        let result = validator.check(key: key, email: email)
        guard result == .valid else {
            reporter.report(.licenseEntryFailed)
            return result
        }
        preferences.licenseEmail = LicenseValidator.normalize(email)
        preferences.licenseKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        refreshEntitlement()
        resetTrialSession()
        return .valid
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
        guard entitlement == .trialExpired, isWindowVisible,
              sessionTimer == nil, !isTrialOverlayShown,
              let deviceID = trialDeviceKey else { return }
        let remaining = sessionBudgets[deviceID] ?? sessionLimit
        activeSessionDeviceID = deviceID
        guard remaining > 0 else {
            showTrialPause()
            return
        }
        let deadline = now().addingTimeInterval(remaining)
        sessionEndsAt = deadline
        window.setTrialCountdown(endsAt: deadline)
        sessionTimer = Task { [weak self] in
            guard let self else { return }
            await sleep(.seconds(remaining))
            guard !Task.isCancelled else { return }
            guard isWindowVisible, entitlement == .trialExpired else { return }
            sessionBudgets[deviceID] = 0
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
        if let deadline = sessionEndsAt, let deviceID = activeSessionDeviceID {
            sessionBudgets[deviceID] = max(0, deadline.timeIntervalSince(now()))
            sessionEndsAt = nil
            window.setTrialCountdown(endsAt: nil)
        }
        activeSessionDeviceID = nil
        if isTrialOverlayShown {
            isTrialOverlayShown = false
            window.setTrialOverlay(false)
        }
    }

    // A licence makes the gate moot: clear the display and forget the budget entirely.
    private func resetTrialSession() {
        suspendTrialSession()
        sessionBudgets.removeAll()
        activeSessionDeviceID = nil
    }
}

/// ── Wireless feed: status, hosted layer, lost share ──
extension AppModel {
    static let wirelessSourceID = "wireless"
    private static let wirelessLog = Logger(
        subsystem: "com.jonyardley.sharepad",
        category: "wireless"
    )

    // Wireless W1 is unauthenticated, so it never ships: Debug builds only until
    // pairing lands (specs/wireless-product.md §10, W2).
    fileprivate static func debugWirelessSource() -> WirelessFeeding? {
        #if DEBUG
            WirelessReceiver()
        #else
            nil
        #endif
    }

    var isSharing: Bool {
        state.isLive
    }

    var isCameraAccessDenied: Bool {
        access == .denied
    }

    var thumbnailLayer: CALayer {
        source(for: hostedFeed).thumbnailLayer
    }

    private var usbInput: SourceInput {
        SourceInput(available: currentDeviceName != nil, running: isLive, failed: failed)
    }

    func selectSource(id: String) {
        if id == Self.wirelessSourceID {
            selectWireless()
        } else {
            selectDevice(id: id)
        }
    }

    func selectWireless() {
        preferredFeed = .wireless
        syncHostedFeed()
    }

    func openLocalNetworkSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocalNetwork"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    var sourceOptions: [SourceOption] {
        let peer = wirelessStatus.peer
        var options = devices.map {
            SourceOption(id: $0.id, label: peer == nil ? $0.name : "\($0.name) · Cable")
        }
        if let peer {
            options.append(SourceOption(id: Self.wirelessSourceID, label: "\(peer.name) · Wi-Fi"))
        }
        return options
    }

    var selectedSourceID: String {
        hostedFeed == .wireless ? Self.wirelessSourceID : currentDeviceID ?? ""
    }

    private var hostedVideoSize: CGSize? {
        hostedFeed == .usb ? videoSize : wirelessVideoSize
    }

    private var trialDeviceKey: String? {
        guard hostedFeed == .wireless else { return currentDeviceID }
        return wirelessStatus.peer.map { "wireless:\($0.id.uuidString)" }
    }

    private func source(for feed: FeedKind) -> FeedSource {
        if feed == .wireless, let wireless { return wireless }
        return capture
    }

    private func observeWireless(_ source: WirelessFeeding) async {
        for await status in source.statuses {
            applyWireless(status)
        }
    }

    private func observeWirelessSizes(_ source: WirelessFeeding) async {
        for await size in source.videoSizes {
            wirelessVideoSize = size
            if isWindowVisible, hostedFeed == .wireless {
                window.updateSize(size)
            }
        }
    }

    func applyWireless(_ status: WirelessStatus) {
        let lostPeer = wirelessStatus.peer != nil && status.peer == nil
        wirelessStatus = status
        if status.peer == nil {
            wirelessVideoSize = nil
            autoShownPeerID = nil
        }
        syncHostedFeed()
        let hosted = String(describing: hostedFeed)
        let visible = isWindowVisible
        let autoShow = autoShowOnConnect
        Self.wirelessLog.notice("""
        status peer=\(status.peer != nil) receiving=\(status.isReceiving) \
        reconnecting=\(status.isReconnecting) hosted=\(hosted, privacy: .public) \
        visible=\(visible) autoShow=\(autoShow)
        """)
        guard hostedFeed == .wireless else { return }
        if lostPeer, isWindowVisible || window.isShowing {
            window.hide()
            setWindowVisible(false, "wireless link ended")
            suspendTrialSession()
            raiseShareLost()
        } else {
            autoShowWirelessIfDue()
        }
    }

    // Every change goes through here so the W1 hardware log shows which path moved
    // it; the window itself is reported alongside, since the two have diverged.
    private func setWindowVisible(_ visible: Bool, _ reason: StaticString) {
        #if DEBUG
            let was = isWindowVisible
            let showing = window.isShowing
            let why = String(describing: reason)
            Self.wirelessLog.notice("""
            windowVisible \(was) -> \(visible) by \(why, privacy: .public) showing=\(showing)
            """)
        #endif
        isWindowVisible = visible
    }

    // Once per link, level-triggered: the first frame can land before the wireless
    // feed is the hosted one, and a user who hides the window keeps it hidden.
    private func autoShowWirelessIfDue() {
        guard hostedFeed == .wireless, wirelessStatus.isReceiving,
              let peer = wirelessStatus.peer, autoShownPeerID != peer.id else { return }
        autoShownPeerID = peer.id
        dismissShareLost()
        guard autoShowOnConnect, !isWindowVisible else { return }
        Self.wirelessLog.notice("auto-showing the share window for a wireless feed")
        presentWindow()
    }

    // A cable that fails or goes while another feed can take over hands the window
    // to that feed instead of ending the share.
    @discardableResult
    private func hideIfShowingUSB() -> Bool {
        syncHostedFeed()
        guard hostedFeed == .usb else { return false }
        window.hide()
        setWindowVisible(false, "cable share ended")
        suspendTrialSession()
        return true
    }

    func syncHostedFeed() {
        guard let feed = AppState.activeFeed(
            camera: access,
            usb: usbInput,
            wireless: wirelessStatus.input,
            preferred: preferredFeed
        ), feed != hostedFeed else { return }
        hostedFeed = feed
        window.setFeedLayer(source(for: feed).hostedLayer)
        if isWindowVisible {
            if let size = hostedVideoSize { window.updateSize(size) }
            suspendTrialSession()
            armOrResumeTrialSession()
        }
        autoShowWirelessIfDue()
    }
}

// ── Settings ──

extension AppModel {
    func setAutoShow(_ enabled: Bool) {
        autoShowOnConnect = enabled
        preferences.autoShowOnConnect = enabled
    }

    func setKeepOnTop(_ enabled: Bool) {
        keepOnTop = enabled
        preferences.keepOnTop = enabled
        window.setKeepOnTop(enabled)
    }

    func setDiagnosticsEnabled(_ enabled: Bool) {
        diagnosticsEnabled = enabled
        preferences.diagnosticsEnabled = enabled
        reporter.refreshSubscription()
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
}

// ── What's new ──

extension AppModel {
    func checkWhatsNew() async {
        guard let appVersion else { return }
        let decision = WhatsNew.decide(
            lastSeen: preferences.lastSeenVersion,
            isFreshInstall: isFreshInstall,
            current: appVersion,
            featureReleases: featureReleases
        )
        switch decision {
        case .show:
            await sleep(Self.whatsNewSettle)
            isWhatsNewDue = true
            presentWhatsNewIfDue()
        case .recordSilently:
            preferences.lastSeenVersion = appVersion
        case .leave:
            break
        }
    }

    func markWhatsNewSeen() {
        guard let appVersion else { return }
        preferences.lastSeenVersion = appVersion
    }

    // A share that ends by accident (cable pulled, Wi-Fi dropped) is likely mid-call,
    // so it waits out the share-lost notice rather than popping up on the meeting.
    private func presentWhatsNewIfDue() {
        guard isWhatsNewDue, !isWindowVisible, !window.isShowing, !shareLostSignal
        else { return }
        isWhatsNewDue = false
        onWhatsNewRequested?()
    }
}
