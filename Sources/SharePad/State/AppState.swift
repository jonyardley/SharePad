enum CameraAccess {
    case unknown
    case denied
    case restricted
    case granted
}

enum AppState: Equatable {
    case checkingPermission
    case permissionDenied
    case permissionRestricted
    case noDevice
    case starting
    case live
    case failed
}

extension AppState {
    // Pure: (permission, device, session) → state. No AVFoundation, so it's unit-
    // testable without hardware (DESIGN.md §5.3 / §11).
    static func reduce(access: CameraAccess, hasDevice: Bool, isRunning: Bool,
                       failed: Bool) -> AppState {
        switch access {
        case .unknown: .checkingPermission
        case .denied: .permissionDenied
        // Restricted (MDM / Screen Time policy) is distinct from denied: the user
        // can't grant it themselves, so the UI must not offer an Open-Settings CTA.
        case .restricted: .permissionRestricted
        case .granted:
            if !hasDevice {
                .noDevice
            } else if failed {
                .failed
            } else {
                isRunning ? .live : .starting
            }
        }
    }
}
