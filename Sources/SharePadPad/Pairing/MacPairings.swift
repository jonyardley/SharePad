import Foundation
import os
import SharePadWire

// The Macs this iPad is paired with, their health, and the pairing flow in progress.
// The link reads `macs` through `onChange`; views read the derived state.
@Observable
@MainActor
final class MacPairings {
    private(set) var macs: [PairingRecord] = []
    private(set) var phase = PadPairing.Phase.idle
    private(set) var saveFailed = false
    private(set) var storeFailed = false
    private(set) var typedCode = ""
    private var broken: Set<UUID> = []

    let identity: Hello

    var state: PairingState {
        PairingState(records: macs, broken: broken)
    }

    var screen: PairingScreenContent {
        PairingScreenContent(phase: phase, saveFailed: saveFailed, hasPairings: !macs.isEmpty)
    }

    var isTypedCodeComplete: Bool {
        TypedCode.code(from: typedCode) != nil
    }

    var pairButtonTitle: String {
        macs.isEmpty ? "Pair with your Mac…" : "Pair another Mac…"
    }

    @ObservationIgnored var onChange: ([PairingRecord]) -> Void = { _ in }
    @ObservationIgnored private let store: PairingStore
    @ObservationIgnored private var book = PairingBook()
    @ObservationIgnored private var health = PairingHealth()
    @ObservationIgnored private var session: PairingSession?
    @ObservationIgnored private let log = Logger(subsystem: "co.sharepad.ipad", category: "pairing")

    init(store: PairingStore, deviceName: String) {
        self.store = store
        let deviceID = try? store.localDeviceID()
        let loaded = Result { try store.loadPairings() }
        identity = Hello(deviceID: deviceID ?? UUID(), deviceName: deviceName)
        _ = book.reduce(.loaded((try? loaded.get()) ?? []))
        macs = book.records
        storeFailed = deviceID == nil || (try? loaded.get()) == nil
    }

    // ── Intents ──

    func reset() {
        session?.cancel()
        phase = .idle
        saveFailed = false
        typedCode = ""
    }

    func setTypedCode(_ text: String) {
        typedCode = TypedCode.format(text)
    }

    func pairWithTypedCode() {
        guard let code = TypedCode.code(from: typedCode) else { return }
        start(code)
    }

    @discardableResult
    func pairWithScannedCode(_ text: String) -> Bool {
        guard let code = TypedCode.code(scanned: text) else { return false }
        start(code)
        return true
    }

    func start(_ code: PairingCode) {
        saveFailed = false
        let session = session ?? PairingSession(
            identity: identity,
            store: store,
            onUpdate: { [weak self] update in self?.sessionUpdate(update) }
        )
        self.session = session
        session.start(code)
    }

    func cancel() {
        session?.cancel()
    }

    func forget(id: UUID) {
        _ = health.reduce(.handshakeSucceeded(id))
        broken.remove(id)
        applyBook(book.reduce(.forget(peerID: id)))
    }

    func linkEvent(_ event: StreamSender.PairedEvent) {
        switch event {
        case let .connected(macID):
            applyHealth(health.reduce(.handshakeSucceeded(macID)))
            applyBook(book.reduce(.connected(peerID: macID, at: Date().timeIntervalSince1970)))
        case let .handshakeFailed(macID):
            applyHealth(health.reduce(.handshakeFailed(macID)))
        }
    }

    // ── Effects ──

    private func sessionUpdate(_ update: PairingSession.Update) {
        switch update {
        case let .phase(phase):
            self.phase = phase
        case let .saved(record):
            _ = health.reduce(.handshakeSucceeded(record.peerID))
            broken.remove(record.peerID)
            applyBook(book.reduce(.paired(record)))
        case .saveFailed:
            saveFailed = true
        }
    }

    private func applyHealth(_ effects: [PairingHealth.Effect]) {
        for effect in effects {
            switch effect {
            case let .markBroken(id): broken.insert(id)
            case let .markHealthy(id): broken.remove(id)
            }
        }
    }

    private func applyBook(_ effects: [PairingBook.Effect]) {
        var credentialsChanged = false
        for effect in effects {
            switch effect {
            case let .save(record):
                persist { try store.savePairing(record) }
            case let .delete(peerID):
                persist { try store.deletePairing(peerID: peerID) }
            case .dropConnections, .reloadCredentials:
                credentialsChanged = true
            }
        }
        macs = book.records
        if credentialsChanged { onChange(book.records) }
    }

    private func persist(_ write: () throws -> Void) {
        do {
            try write()
            storeFailed = false
        } catch {
            log.error("pairing store write failed: \(error.localizedDescription)")
            storeFailed = true
        }
    }
}
