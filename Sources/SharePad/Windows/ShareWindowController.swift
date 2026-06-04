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

    func show() {
        let window = window ?? makeWindow()
        self.window = window
        window.makeKeyAndOrderFront(nil)
    }

    func hide() {
        window?.orderOut(nil)
    }

    private func makeWindow() -> NSWindow {
        let hosting = NSHostingController(rootView: PreviewView(previewLayer: previewLayer))
        let window = NSWindow(contentViewController: hosting)
        window.title = "SharePad"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 768, height: 1024))
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
}
