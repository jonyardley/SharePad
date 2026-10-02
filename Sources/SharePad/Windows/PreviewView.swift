import AppKit
import SwiftUI

struct PreviewView: NSViewRepresentable {
    let layer: CALayer

    func makeNSView(context _: Context) -> PreviewNSView {
        let view = PreviewNSView()
        view.wantsLayer = true
        view.host(layer)
        return view
    }

    func updateNSView(_ view: PreviewNSView, context _: Context) {
        guard view.hostedLayer !== layer else { return }
        // The window is in a call: an implicit fade on the swap would go out to it.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        view.hostedLayer?.removeFromSuperlayer()
        view.host(layer)
        CATransaction.commit()
    }
}

final class PreviewNSView: NSView {
    private(set) var hostedLayer: CALayer?

    // Sized now and on every frame change, not only in `layout()`: a window ordered
    // in while the app is inactive can skip that pass, leaving a 1x1 video layer.
    func host(_ layer: CALayer) {
        hostedLayer = layer
        layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        layer.frame = bounds
        self.layer?.addSublayer(layer)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        hostedLayer?.frame = bounds
    }

    override func layout() {
        super.layout()
        hostedLayer?.frame = bounds
    }
}
