import AppKit
import AVFoundation
import os
import SwiftUI

@MainActor
final class ShareWindowController: ShareWindowControlling {
    private var window: NSWindow?
    private let preferences: Preferences
    private var keepOnTop = false
    private var isObserving = false
    private let overlayModel: ShareOverlayModel

    /// The frame as we last set it ourselves. The move/resize observers persist only
    /// when the live frame differs from this, so a programmatic restore/resize never
    /// saves its own (possibly clamped) value back over the user's chosen frame.
    private var appliedFrame: CGRect?

    private static let defaultLongSide: CGFloat = 900

    init(previewLayer: AVCaptureVideoPreviewLayer, preferences: Preferences) {
        self.preferences = preferences
        overlayModel = ShareOverlayModel(feedLayer: previewLayer)
    }

    func setFeedLayer(_ layer: CALayer) {
        overlayModel.feedLayer = layer
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
        #if DEBUG
            logIdentity("shown")
            logPresentation(of: window)
        #endif
    }

    #if DEBUG
        private func logIdentity(_ moment: String) {
            let shareWindows = NSApp.windows.filter { $0.identifier == WindowSharing.shareWindowID }
            let identity = window.map { String(describing: ObjectIdentifier($0)) } ?? "none"
            let onScreen = shareWindows.filter(\.isVisible).count
            Logger(subsystem: "com.jonyardley.sharepad", category: "window").notice("""
            \(moment, privacy: .public) window=\(identity, privacy: .public) \
            shareWindows=\(shareWindows.count) onScreen=\(onScreen)
            """)
        }

        // Wireless W1 hardware check: records whether a shown window is really on
        // screen and hosting the feed layer, since a call shares only what composites.
        private func logPresentation(of window: NSWindow) {
            let log = Logger(subsystem: "com.jonyardley.sharepad", category: "window")
            let describe = { [overlayModel] (moment: String) in
                let layer = overlayModel.feedLayer
                let frame = String(describing: window.frame)
                let kind = String(describing: type(of: layer))
                let bounds = String(describing: layer.bounds)
                let chain = Self.layerChain(from: layer, upTo: window.contentView?.layer)
                let content = String(describing: window.contentView?.frame ?? .zero)
                log.notice("""
                \(moment, privacy: .public): visible=\(window.isVisible) \
                occludedVisible=\(window.occlusionState.contains(.visible)) \
                activeSpace=\(window.isOnActiveSpace) appActive=\(NSApp.isActive) \
                level=\(window.level.rawValue) frame=\(frame, privacy: .public) \
                layer=\(kind, privacy: .public) attached=\(layer.superlayer != nil) \
                bounds=\(bounds, privacy: .public) content=\(content, privacy: .public)
                """)
                log.notice("\(moment, privacy: .public) chain: \(chain, privacy: .public)")
            }
            describe("shown")
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                describe("one second after show")
            }
        }
    #endif

    #if DEBUG
        // Each step from the feed layer up to the window's root: what would stop it
        // compositing (zero bounds, hidden, transparent, or a sibling above it).
        static func layerChain(from layer: CALayer, upTo root: CALayer?) -> String {
            var steps: [String] = []
            var current: CALayer? = layer
            while let step = current {
                let siblings = step.superlayer?.sublayers ?? [step]
                let index = siblings.firstIndex { $0 === step } ?? -1
                steps.append(
                    "\(type(of: step))[\(step.bounds.integral) hidden=\(step.isHidden) " +
                        "opacity=\(step.opacity) z=\(step.zPosition) scale=\(step.contentsScale) " +
                        "at=\(index + 1)/\(siblings.count)]"
                )
                if step === root { break }
                current = step.superlayer
            }
            return steps.joined(separator: " < ")
        }
    #endif

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
        #if DEBUG
            logIdentity("hidden")
        #endif
    }

    var isShowing: Bool {
        window?.isVisible ?? false
    }

    func setTrialOverlay(_ visible: Bool) {
        overlayModel.trialOverlayVisible = visible
    }

    func setTrialCountdown(endsAt: Date?) {
        overlayModel.sessionEndsAt = endsAt
    }

    func setTrialActions(onBuy: (() -> Void)?, onEnterLicense: @escaping () -> Void) {
        overlayModel.onBuy = onBuy
        overlayModel.onEnterLicense = onEnterLicense
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
            rootView: ShareRootView(overlay: overlayModel)
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
    var feedLayer: CALayer
    var trialOverlayVisible = false
    var sessionEndsAt: Date?
    var onBuy: (() -> Void)?
    var onEnterLicense: () -> Void = {}

    init(feedLayer: CALayer) {
        self.feedLayer = feedLayer
    }
}

private struct ShareRootView: View {
    let overlay: ShareOverlayModel

    var body: some View {
        ZStack {
            PreviewView(layer: overlay.feedLayer)
            if overlay.trialOverlayVisible {
                TrialOverlayView(onBuy: overlay.onBuy, onEnterLicense: overlay.onEnterLicense)
            } else if let endsAt = overlay.sessionEndsAt {
                TrialCountdownWatermark(endsAt: endsAt)
            }
        }
    }
}
