import AppKit
import AVFoundation
import SwiftUI

@MainActor
final class ShareWindowController {
    private var window: NSWindow?
    private let previewLayer: AVCaptureVideoPreviewLayer

    init(previewLayer: AVCaptureVideoPreviewLayer) {
        self.previewLayer = previewLayer
    }

    func present(size: CGSize) {
        let window = window ?? makeWindow()
        self.window = window
        window.contentAspectRatio = size
        window.setContentSize(contentSize(for: size))
        if !window.isVisible {
            window.center()
            window.makeKeyAndOrderFront(nil)
        }
    }

    func hide() {
        window?.orderOut(nil)
    }

    private func makeWindow() -> BorderlessWindow {
        let window = BorderlessWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 800),
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = NSHostingController(
            rootView: PreviewView(previewLayer: previewLayer)
        )
        window.isMovableByWindowBackground = true
        window.backgroundColor = .black
        window.hasShadow = true
        window.isReleasedWhenClosed = false
        return window
    }

    private func contentSize(for videoSize: CGSize) -> NSSize {
        let maxLongSide: CGFloat = 900
        let longSide = max(videoSize.width, videoSize.height)
        guard longSide > 0 else { return NSSize(width: 600, height: 800) }
        let scale = min(1, maxLongSide / longSide)
        return NSSize(width: videoSize.width * scale, height: videoSize.height * scale)
    }
}
