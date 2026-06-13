import AppKit
import AVFoundation
import SwiftUI

@MainActor
final class ShareWindowController: ShareWindowControlling {
    private var window: NSWindow?
    private let previewLayer: AVCaptureVideoPreviewLayer
    private let preferences: Preferences
    private var keepOnTop = false
    private var isObserving = false
    private let overlayModel = ShareOverlayModel()

    /// The frame as we last set it ourselves. The move/resize observers persist only
    /// when the live frame differs from this, so a programmatic restore/resize never
    /// saves its own (possibly clamped) value back over the user's chosen frame.
    private var appliedFrame: CGRect?

    private static let defaultLongSide: CGFloat = 900

    init(previewLayer: AVCaptureVideoPreviewLayer, preferences: Preferences) {
        self.previewLayer = previewLayer
        self.preferences = preferences
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
        startObserving()
        apply(size: size, to: window)
        restoreOrigin(of: window)
        appliedFrame = window.frame
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    /// Driven by iPad rotation, not the user — so adapt the live window (keeping its
    /// centre) but don't persist. Overwriting the saved origin here would discard the
    /// user's chosen placement on every rotation; only their own move/resize persists.
    /// `appliedFrame` is refreshed so the move observer doesn't treat this as a user move.
    func updateSize(_ size: CGSize) {
        guard let window else { return }
        let oldFrame = window.frame
        apply(size: size, to: window)
        window.setFrameOrigin(centeredResizeOrigin(
            oldFrame: oldFrame,
            newSize: window.frame.size,
            onScreens: screenFrames()
        ))
        appliedFrame = window.frame
    }

    func hide() {
        window?.orderOut(nil)
    }

    func setTrialOverlay(_ visible: Bool) {
        overlayModel.trialOverlayVisible = visible
    }

    private func apply(size videoSize: CGSize, to window: NSWindow) {
        window.level = keepOnTop ? .floating : .normal
        window.contentAspectRatio = videoSize
        let longSide = preferences.windowLongSide ?? Self.defaultLongSide
        window.setContentSize(fittedContentSize(for: videoSize, maxLongSide: longSide))
    }

    private func restoreOrigin(of window: NSWindow) {
        if let saved = preferences.windowOrigin,
           let placed = placedOrigin(
               savedOrigin: saved,
               size: window.frame.size,
               onScreens: screenFrames()
           ) {
            window.setFrameOrigin(placed)
        } else {
            window.center()
        }
    }

    private func persistFrame() {
        guard let window else { return }
        preferences.windowOrigin = window.frame.origin
        let content = window.contentRect(forFrameRect: window.frame).size
        preferences.windowLongSide = max(content.width, content.height)
    }

    private func screenFrames() -> [CGRect] {
        NSScreen.screens.map(\.visibleFrame)
    }

    private func startObserving() {
        guard !isObserving else { return }
        isObserving = true
        for name in [NSWindow.didMoveNotification, NSWindow.didEndLiveResizeNotification] {
            Task { [weak self] in
                guard let window = self?.window else { return }
                for await _ in NotificationCenter.default.notifications(
                    named: name,
                    object: window
                ) {
                    guard let self else { return }
                    guard let applied = appliedFrame, applied != window.frame else { continue }
                    persistFrame()
                }
            }
        }
    }

    private func makeWindow() -> BorderlessWindow {
        let window = BorderlessWindow(
            contentRect: NSRect(origin: .zero, size: fallbackContentSize),
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = NSHostingController(
            rootView: ShareRootView(previewLayer: previewLayer, overlay: overlayModel)
        )
        window.isMovableByWindowBackground = true
        window.backgroundColor = .black
        window.hasShadow = true
        window.isReleasedWhenClosed = false
        // Tagged so WindowSharing keeps the feed capturable while excluding every
        // other window; titled so it's the clearly-named pick in a call's picker.
        window.identifier = WindowSharing.shareWindowID
        window.title = "SharePad"
        return window
    }
}

// The trial overlay lives *inside* the window's SwiftUI root (a ZStack over the
// preview) rather than as a foreign NSHostingView subview — the latter doesn't
// reliably composite above the layer-backed preview. Driven by an @Observable flag.
@MainActor
@Observable
final class ShareOverlayModel {
    var trialOverlayVisible = false
}

private struct ShareRootView: View {
    let previewLayer: AVCaptureVideoPreviewLayer
    let overlay: ShareOverlayModel

    var body: some View {
        ZStack {
            PreviewView(layer: previewLayer)
            if overlay.trialOverlayVisible {
                TrialOverlayView()
            }
        }
    }
}
