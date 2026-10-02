import Foundation

enum Overlay: Hashable, Sendable {
    case paperMenu
    case settings
}

struct FrameGate: Equatable, Sendable {
    // Covers a sheet or popover's dismissal animation, which still draws over the
    // canvas after the presenting binding has gone false.
    static let settle: TimeInterval = 0.4

    private var overlays: Set<Overlay> = []
    private var heldUntil: TimeInterval = 0

    mutating func overlay(_ overlay: Overlay, shown: Bool, at now: TimeInterval) {
        if shown {
            overlays.insert(overlay)
        } else if overlays.remove(overlay) != nil {
            heldUntil = max(heldUntil, now + Self.settle)
        }
    }

    func allowsFrame(at now: TimeInterval) -> Bool {
        overlays.isEmpty && now >= heldUntil
    }
}
