import CoreVideo
import Foundation
import os
import SharePadWire

final class CaptureContext: Sendable {
    struct Decision: Equatable {
        let allowed: Bool
        let crop: CanvasRect?
    }

    private struct State {
        var gate = FrameGate()
        var layout: CanvasLayout?
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    func overlay(_ overlay: Overlay, shown: Bool, at now: TimeInterval) {
        state.withLock { $0.gate.overlay(overlay, shown: shown, at: now) }
    }

    func setLayout(_ layout: CanvasLayout) {
        state.withLock { $0.layout = layout }
    }

    func decide(for frame: CapturedFrame, at now: TimeInterval) -> Decision {
        let (gate, layout) = state.withLock { ($0.gate, $0.layout) }
        guard gate.allowsFrame(at: now), let layout else {
            return Decision(allowed: false, crop: nil)
        }
        let crop = CanvasCrop.pixelRect(
            for: layout,
            bufferWidth: CVPixelBufferGetWidth(frame.pixelBuffer),
            bufferHeight: CVPixelBufferGetHeight(frame.pixelBuffer),
            orientation: frame.orientation
        )
        return Decision(allowed: crop != nil, crop: crop)
    }
}
