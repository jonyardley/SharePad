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

    func setLayout(_ layout: CanvasLayout, at now: TimeInterval) {
        state.withLock { state in
            let changed = state.layout.map(CanvasCrop.shareableRect) != CanvasCrop
                .shareableRect(of: layout)
            if changed, state.layout != nil {
                state.gate.hold(for: FrameGate.recrop, at: now)
            }
            state.layout = layout
        }
    }

    func decide(for frame: CapturedFrame, at now: TimeInterval) -> Decision {
        let (gate, layout) = state.withLock { ($0.gate, $0.layout) }
        guard let layout else { return Decision(allowed: false, crop: nil) }
        let crop = CanvasCrop.pixelRect(
            for: layout,
            bufferWidth: CVPixelBufferGetWidth(frame.pixelBuffer),
            bufferHeight: CVPixelBufferGetHeight(frame.pixelBuffer),
            orientation: frame.orientation
        )
        return Decision(allowed: crop != nil && gate.allowsFrame(at: now), crop: crop)
    }
}
