import AVFoundation
import SwiftUI

struct PreviewView: NSViewRepresentable {
    let previewLayer: AVCaptureVideoPreviewLayer

    func makeNSView(context _: Context) -> PreviewNSView {
        let view = PreviewNSView()
        view.wantsLayer = true
        view.hostedLayer = previewLayer
        view.layer?.addSublayer(previewLayer)
        return view
    }

    func updateNSView(_: PreviewNSView, context _: Context) {}
}

final class PreviewNSView: NSView {
    var hostedLayer: CALayer?

    override func layout() {
        super.layout()
        hostedLayer?.frame = bounds
    }
}
