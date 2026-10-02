import Foundation
import os
import PencilKit
import SwiftUI
import UIKit

@Observable
@MainActor
final class PadModel {
    static let saveDelay: Duration = .seconds(1)

    private(set) var paper: Paper
    private(set) var linkStatus = LinkStatus.idle
    private(set) var localNetworkDenied = false
    private(set) var canUndo = false
    private(set) var canRedo = false
    private(set) var toolsUnlocated = false
    private(set) var rules = StreamingRules()

    var isPaperMenuShown = false {
        didSet { overlayChanged(.paperMenu, shown: isPaperMenuShown, was: oldValue) }
    }

    var isSettingsShown = false {
        didSet { overlayChanged(.settings, shown: isSettingsShown, was: oldValue) }
    }

    let canvas: CanvasController
    let isDevelopmentBuild: Bool

    var pill: ConnectionPill {
        ConnectionPill(
            link: linkStatus,
            localNetworkDenied: localNetworkDenied,
            captureDeclined: rules.captureDeclined,
            toolsUnlocated: toolsUnlocated
        )
    }

    var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    @ObservationIgnored private let preferences: PadPreferences
    @ObservationIgnored private let drawingStore: DrawingStore
    @ObservationIgnored private let recorder: ScreenRecording
    @ObservationIgnored private let captureContext = CaptureContext()
    @ObservationIgnored private var pendingSave: Task<Void, Never>?
    @ObservationIgnored private let log = Logger(subsystem: "co.sharepad.ipad", category: "model")
    @ObservationIgnored private lazy var link: StreamLink = StreamLinks.make(
        lastMac: preferences.lastMac,
        callbacks: LinkCallbacks(
            onStatus: { [weak self] status in self?.linkChanged(status) },
            onLocalNetworkDenied: { [weak self] denied in self?.localNetworkDenied = denied }
        )
    )

    init(
        preferences: PadPreferences = PadPreferences(),
        drawingStore: DrawingStore = .applicationSupport(),
        recorder: ScreenRecording = ScreenRecorder()
    ) {
        self.preferences = preferences
        self.drawingStore = drawingStore
        self.recorder = recorder
        paper = preferences.paper
        #if DEBUG
            isDevelopmentBuild = true
        #else
            isDevelopmentBuild = false
        #endif
        canvas = CanvasController(drawing: drawingStore.load())
        canvas.apply(tone: paper.tone)
        canvas.onDrawingChange = { [weak self] _ in self?.scheduleSave() }
        canvas.onUndoChange = { [weak self] canUndo, canRedo in
            self?.canUndo = canUndo
            self?.canRedo = canRedo
        }
        let context = captureContext
        canvas.onLayoutChange = { layout in
            context.setLayout(layout, at: ProcessInfo.processInfo.systemUptime)
        }
        canvas
            .onToolsUnlocated = { [weak self] unlocated in self?.toolsUnlocatedChanged(unlocated) }
        UIApplication.shared.applicationSupportsShakeToEdit = false
    }

    // ── Intents ──

    func sceneChanged(_ phase: ScenePhase) {
        switch phase {
        case .active:
            apply(.scene(.active))
        case .background:
            saveNow()
            apply(.scene(.background))
        default:
            apply(.scene(.inactive))
        }
    }

    func setPaper(_ paper: Paper) {
        self.paper = paper
        preferences.paper = paper
        canvas.apply(tone: paper.tone)
    }

    func undo() {
        canvas.undo()
    }

    func redo() {
        canvas.redo()
    }

    func clear() {
        canvas.clear()
    }

    func pillAction(_ action: ConnectionPill.Action) {
        switch action {
        case .openSettings:
            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
            UIApplication.shared.open(url)
        case .retryCapture:
            apply(.retryCapture)
        }
    }

    // ── Streaming ──

    private func linkChanged(_ status: LinkStatus) {
        linkStatus = status
        if let mac = status.liveMac, mac != preferences.lastMac {
            preferences.lastMac = mac
        }
        apply(.linkUp(status.isUp))
    }

    private func apply(_ event: StreamingRules.Event) {
        let effects = rules.reduce(event)
        effects.forEach(perform)
        UIApplication.shared.isIdleTimerDisabled = rules.capture == .running
    }

    private func perform(_ effect: StreamingRules.Effect) {
        switch effect {
        case .startLink:
            link.start()
        case .stopLink:
            link.stop()
        case .startCapture:
            recorder.start(onFrame: frameSink()) { [weak self] started in
                self?.apply(started ? .captureStarted : .captureFailed)
            }
        case .stopCapture:
            recorder.stop { [weak self] in self?.apply(.captureStopped) }
        case let .scheduleHold(id, delay):
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(delay))
                self?.apply(.holdElapsed(id))
            }
        }
    }

    private func frameSink() -> @Sendable (CapturedFrame) -> Void {
        let context = captureContext
        let link = link
        return { frame in
            let decision = context.decide(for: frame, at: ProcessInfo.processInfo.systemUptime)
            if let crop = decision.crop { link.setCanvas(crop) }
            guard decision.allowed else { return }
            link.submit(
                pixelBuffer: frame.pixelBuffer,
                presentationTime: frame.presentationTime,
                captureWallClock: Date().timeIntervalSince1970
            )
        }
    }

    private func toolsUnlocatedChanged(_ unlocated: Bool) {
        guard unlocated != toolsUnlocated else { return }
        toolsUnlocated = unlocated
        captureContext.overlay(
            .unlocatedTools,
            shown: unlocated,
            at: ProcessInfo.processInfo.systemUptime
        )
    }

    private func overlayChanged(_ overlay: Overlay, shown: Bool, was: Bool) {
        guard shown != was else { return }
        captureContext.overlay(overlay, shown: shown, at: ProcessInfo.processInfo.systemUptime)
        guard !shown else { return }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(FrameGate.settle))
            self?.canvas.showToolPicker()
        }
    }

    // ── Drawing ──

    private func scheduleSave() {
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            try? await Task.sleep(for: Self.saveDelay)
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    private func saveNow() {
        pendingSave?.cancel()
        pendingSave = nil
        do {
            try drawingStore.save(canvas.drawing)
        } catch {
            log.error("could not save the drawing: \(error.localizedDescription)")
        }
    }
}
