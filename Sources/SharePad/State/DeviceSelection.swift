// Pure: (devices, current, last-used) → chosen device. No AVFoundation, so it's
// unit-testable without hardware (DESIGN.md §11).
func pickDevice(from devices: [CaptureDevice], current: String?,
                lastUsed: String?) -> CaptureDevice? {
    if let current, let match = devices.first(where: { $0.id == current }) {
        return match
    }
    if let lastUsed, let match = devices.first(where: { $0.id == lastUsed }) {
        return match
    }
    return devices.first
}

enum DeviceResolution: Equatable {
    case teardown
    case keep(CaptureDevice)
    case switchTo(CaptureDevice)
}

func resolveDevice(devices: [CaptureDevice], current: String?,
                   lastUsed: String?) -> DeviceResolution {
    guard let chosen = pickDevice(from: devices, current: current, lastUsed: lastUsed) else {
        return .teardown
    }
    return chosen.id == current ? .keep(chosen) : .switchTo(chosen)
}
