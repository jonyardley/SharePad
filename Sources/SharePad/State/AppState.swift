enum CameraAccess {
    case unknown
    case denied
    case granted
}

enum AppState: Equatable {
    case checkingPermission
    case permissionDenied
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
