import AppKit
import AVFoundation
import SwiftUI

@MainActor
final class ShareWindowController {
    private var window: NSWindow?
    private let previewLayer: AVCaptureVideoPreviewLayer
    private var keepOnTop = false

    init(previewLayer: AVCaptureVideoPreviewLayer) {
        self.previewLayer = previewLayer
    }

    func setKeepOnTop(_ enabled: Bool) {
        keepOnTop = enabled
        window?.level = enabled ? .floating : .normal
    }

    /// Bring the window (and app) to the front. Without activation an accessory app's
    /// window orders in *behind* the active app, so the user never sees it.
    func show(size: CGSize) {
        let window = window ?? makeWindow()
        self.window = window
        let firstShow = !window.isVisible
        apply(size: size, to: window)
        if firstShow { window.center() }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func updateSize(_ size: CGSize) {
        guard let window else { return }
        apply(size: size, to: window)
    }

    private func apply(size: CGSize, to window: NSWindow) {
        window.level = keepOnTop ? .floating : .normal
        window.contentAspectRatio = size
        window.setContentSize(fittedContentSize(for: size))
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
}

func fittedContentSize(for videoSize: CGSize, maxLongSide: CGFloat = 900) -> CGSize {
    let longSide = max(videoSize.width, videoSize.height)
    guard longSide > 0 else { return CGSize(width: 600, height: 800) }
    let scale = min(1, maxLongSide / longSide)
    return CGSize(width: videoSize.width * scale, height: videoSize.height * scale)
}
