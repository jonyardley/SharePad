import Foundation
import os
import PencilKit
import SharePadWire
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

    var isPairingShown = false {
        didSet { pairingShownChanged(was: oldValue) }
    }

    let canvas: CanvasController
    let pairings: MacPairings

    var pill: ConnectionPill {
        ConnectionPill(
            link: linkStatus,
            pairing: pairings.state,
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
    @ObservationIgnored private var pairAfterSettings = false
    @ObservationIgnored private var pendingPairingCode: PairingCode?
    @ObservationIgnored private let drawingStore: DrawingStore
    @ObservationIgnored private let recorder: ScreenRecording
    @ObservationIgnored private let captureContext = CaptureContext()
    @ObservationIgnored private var pendingSave: Task<Void, Never>?
    #if DEBUG
        @ObservationIgnored private let spike: CaptureSpike?
    #endif
    @ObservationIgnored private let log = Logger(subsystem: "co.sharepad.ipad", category: "model")
    @ObservationIgnored private lazy var link: StreamLink = PairedLink(
        identity: pairings.identity,
        lastMac: preferences.lastMac,
        pairings: pairings.macs,
        callbacks: LinkCallbacks(
            onStatus: { [weak self] status in self?.linkChanged(status) },
            onLocalNetworkDenied: { [weak self] denied in self?.localNetworkDenied = denied },
            onPairedEvent: { [weak self] event in self?.pairings.linkEvent(event) },
            onStats: { [weak self] stats in self?.linkStats(stats) }
        )
    )

    init(
        preferences: PadPreferences = PadPreferences(),
        drawingStore: DrawingStore = .applicationSupport(),
        recorder: ScreenRecording = ScreenRecorder(),
        store: PairingStore = KeychainPairingStore()
    ) {
        self.preferences = preferences
        self.drawingStore = drawingStore
        pairings = MacPairings(store: store, deviceName: UIDevice.current.name)
        paper = preferences.paper
        canvas = CanvasController(drawing: drawingStore.load())
        #if DEBUG
            spike = CaptureSpike.fromLaunch(canvas: canvas, paper: preferences.paper)
            self.recorder = spike?.renderer ?? recorder
        #else
            self.recorder = recorder
        #endif
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
        pairings.onChange = { [weak self] records in self?.link.setPairings(records) }
        isPairingShown = pairings.macs.isEmpty
        captureContext.overlay(
            .pairing,
            shown: isPairingShown,
            at: ProcessInfo.processInfo.systemUptime
        )
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
        #if DEBUG
            spike?.renderer?.paper = paper
        #endif
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
        case .pair, .pairAgain:
            showPairing()
        }
    }

    // ── Pairing ──

    func showPairing() {
        showPairing(prefilled: nil)
    }

    // A link only fills the code in: pairing waits for a Pair tap, so a link someone
    // else sends cannot pair this iPad with their Mac unseen.
    func open(_ url: URL) {
        guard let code = PairingCode(invitation: url) else { return }
        showPairing(prefilled: code)
    }

    private func showPairing(prefilled code: PairingCode?) {
        pendingPairingCode = code
        if isSettingsShown {
            pairAfterSettings = true
            isSettingsShown = false
            return
        }
        pairings.reset(typedCode: code)
        isPairingShown = true
    }

    private func pairingShownChanged(was: Bool) {
        if !isPairingShown { pairings.cancel() }
        overlayChanged(.pairing, shown: isPairingShown, was: was)
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
        #if DEBUG
            let probe = spike?.probe
        #endif
        return { frame in
            #if DEBUG
                probe?.captured(frame)
            #endif
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
            guard let self else { return }
            if overlay == .settings, pairAfterSettings {
                pairAfterSettings = false
                showPairing(prefilled: pendingPairingCode)
            } else {
                canvas.showToolPicker()
            }
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

private extension PadModel {
    func linkStats(_ stats: StreamSender.Stats) {
        #if DEBUG
            spike?.sampler.linkStats(stats)
        #endif
    }
}
