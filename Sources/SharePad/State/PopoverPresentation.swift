import Foundation

enum StatusLine: Equatable {
    case checkingPermission
    case cameraOff
    case cameraBlocked
    case localNetworkOff
    case noIPad
    case connecting(FeedKind)
    case sharingOverCable
    case sharingOverWiFi
    case reconnectingOverWiFi
    case failed(FeedKind)

    init(state: AppState, isReconnecting: Bool) {
        switch state {
        case .checkingPermission: self = .checkingPermission
        case .permissionDenied: self = .cameraOff
        case .permissionRestricted: self = .cameraBlocked
        case .localNetworkDenied: self = .localNetworkOff
        case .noDevice: self = .noIPad
        case let .starting(feed): self = .connecting(feed)
        case .live(.usb): self = .sharingOverCable
        case .live(.wireless): self = isReconnecting ? .reconnectingOverWiFi : .sharingOverWiFi
        case let .failed(feed): self = .failed(feed)
        }
    }
}

enum StatusHint: Equatable {
    case pairingStoreFailed
    case listenerFailed
    case plugIn
    case unlockAndTrust
    case checkCable
    case cameraOff
    case cameraBlocked
    case localNetworkOff
    case cableNeedsCamera

    // A connected-but-locked or not-yet-trusted iPad shows up to discovery but never
    // starts a session, so it sits in .starting looking stuck (the hint also flashes
    // briefly on a healthy connect). The app can't tell "locked" from "still trusting".
    init?(state: AppState, wireless: WirelessStatus, cameraDenied: Bool) {
        switch state {
        case .noDevice where wireless.pairingStoreFailed: self = .pairingStoreFailed
        case .noDevice where wireless.listenerFailed: self = .listenerFailed
        case .noDevice: self = .plugIn
        case .starting(.usb): self = .unlockAndTrust
        case .failed(.usb): self = .checkCable
        case .permissionDenied: self = .cameraOff
        case .permissionRestricted: self = .cameraBlocked
        case .localNetworkDenied: self = .localNetworkOff
        case .live(.wireless) where cameraDenied: self = .cableNeedsCamera
        default: return nil
        }
    }
}

enum LicenseStatus: Equatable {
    case licensed
    case trial(daysLeft: Int)
    case paused
    case pausesAt(Date)
    case pausesAfter(minutes: Int)

    init(
        entitlement: Entitlement,
        overlayShown: Bool,
        sessionEndsAt: Date?,
        sessionLimitMinutes: Int
    ) {
        switch entitlement {
        case .licensed:
            self = .licensed
        case let .trial(daysLeft):
            self = .trial(daysLeft: daysLeft)
        case .trialExpired:
            if overlayShown {
                self = .paused
            } else if let sessionEndsAt {
                self = .pausesAt(sessionEndsAt)
            } else {
                self = .pausesAfter(minutes: sessionLimitMinutes)
            }
        }
    }
}
