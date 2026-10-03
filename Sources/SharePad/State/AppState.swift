enum CameraAccess {
    case unknown
    case denied
    case restricted
    case granted
}

enum FeedKind: Equatable, Sendable {
    case usb
    case wireless
}

// Only asked once the wireless listener starts, so a USB-only run stays
// `.notRequested` for its whole life (specs/wireless-product.md §5).
enum LocalNetworkAccess: Equatable, Sendable {
    case notRequested
    case granted
    case denied
}

struct SourceInput: Equatable, Sendable {
    var available = false
    var running = false
    var failed = false

    static let absent = SourceInput()
}

enum AppState: Equatable {
    case checkingPermission
    case permissionDenied
    case permissionRestricted
    case localNetworkDenied
    case noDevice
    case starting(FeedKind)
    case live(FeedKind)
    case failed(FeedKind)

    var activeFeed: FeedKind? {
        switch self {
        case let .starting(feed), let .live(feed), let .failed(feed): feed
        default: nil
        }
    }

    var isLive: Bool {
        if case .live = self {
            true
        } else {
            false
        }
    }
}

extension AppState {
    // Pure: (permission, sources, preference) → state. No AVFoundation or Network, so
    // it's unit-testable without hardware (DESIGN.md §5.3 / §11).
    static func reduce(
        camera: CameraAccess,
        usb: SourceInput,
        wireless: SourceInput,
        localNetwork: LocalNetworkAccess,
        preferred: FeedKind?
    ) -> AppState {
        if let feed = activeFeed(
            camera: camera,
            usb: usb,
            wireless: wireless,
            preferred: preferred
        ) {
            let input = feed == .usb ? usb : wireless
            if input.failed { return .failed(feed) }
            return input.running ? .live(feed) : .starting(feed)
        }
        switch camera {
        case .unknown: return .checkingPermission
        case .denied: return .permissionDenied
        // Restricted (MDM / Screen Time policy) is distinct from denied: the user
        // can't grant it themselves, so the UI must not offer an Open-Settings CTA.
        case .restricted: return .permissionRestricted
        case .granted: return localNetwork == .denied ? .localNetworkDenied : .noDevice
        }
    }

    // A cable without camera access can't run, and a failed or still-starting one
    // shouldn't take the window from a receiving Wi-Fi feed
    // (specs/wireless-product.md §3, decision 6; §10, W4).
    static func activeFeed(
        camera: CameraAccess,
        usb: SourceInput,
        wireless: SourceInput,
        preferred: FeedKind?
    ) -> FeedKind? {
        let usbUsable = camera == .granted && usb.available
        let wirelessReceiving = wireless.available && wireless.running && !wireless.failed
        if preferred == .wireless, wireless.available { return .wireless }
        if wirelessReceiving, !(usbUsable && usb.running) { return .wireless }
        if usbCanHost(camera: camera, usb: usb) { return .usb }
        if wireless.available { return .wireless }
        return usbUsable ? .usb : nil
    }

    // The iPad streams over Wi-Fi only while that feed can be shown: not while the
    // cable holds the window or the trial overlay covers it (§10, W4b).
    static func isWirelessHostActive(
        hosted: FeedKind,
        camera: CameraAccess,
        usb: SourceInput,
        trialOverlayShown: Bool
    ) -> Bool {
        guard !trialOverlayShown else { return false }
        return hosted == .wireless || !usbCanHost(camera: camera, usb: usb)
    }

    private static func usbCanHost(camera: CameraAccess, usb: SourceInput) -> Bool {
        camera == .granted && usb.available && !usb.failed
    }
}
