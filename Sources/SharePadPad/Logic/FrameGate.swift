import Foundation

enum Overlay: Hashable, Sendable {
    case paperMenu
    case settings
    case export
    case pairing
    case unlocatedTools
}

struct FrameGate: Equatable, Sendable {
    // Covers a sheet or popover's dismissal animation, which still draws over the
    // canvas after the presenting binding has gone false.
    static let settle: TimeInterval = 0.4
    // A new crop reaches the Mac only with the next keyframe, and SenderRules spaces
    // forced keyframes by at least 0.5 s; frames before it would show the old crop.
    static let recrop: TimeInterval = 0.6

    private var overlays: Set<Overlay> = []
    private var heldUntil: TimeInterval = 0

    mutating func overlay(_ overlay: Overlay, shown: Bool, at now: TimeInterval) {
        if shown {
            overlays.insert(overlay)
        } else if overlays.remove(overlay) != nil {
            hold(for: Self.settle, at: now)
        }
    }

    mutating func hold(for duration: TimeInterval, at now: TimeInterval) {
        heldUntil = max(heldUntil, now + duration)
    }

    func allowsFrame(at now: TimeInterval) -> Bool {
        overlays.isEmpty && now >= heldUntil
    }
}
