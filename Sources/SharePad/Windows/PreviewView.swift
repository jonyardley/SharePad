import AppKit
import SwiftUI

struct PreviewView: NSViewRepresentable {
    let layer: CALayer

    func makeNSView(context _: Context) -> PreviewNSView {
        let view = PreviewNSView()
        view.wantsLayer = true
        view.hostedLayer = layer
        view.layer?.addSublayer(layer)
        return view
    }

    func updateNSView(_ view: PreviewNSView, context _: Context) {
        guard view.hostedLayer !== layer else { return }
        // The window is in a call: an implicit fade on the swap would go out to it.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        view.hostedLayer?.removeFromSuperlayer()
        view.hostedLayer = layer
        layer.frame = view.bounds
        view.layer?.addSublayer(layer)
        CATransaction.commit()
    }
}

final class PreviewNSView: NSView {
    var hostedLayer: CALayer?

    override func layout() {
        super.layout()
        hostedLayer?.frame = bounds
    }
}
