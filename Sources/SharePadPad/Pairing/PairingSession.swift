import Foundation
import Network
import os
import SharePadWire

// Runs PadPairing against the network: tries each advertising Mac with the code until
// one grants a pairing. The record is saved before the Mac is told, so the Mac never
// keeps a pairing this iPad lost (specs/wireless-product.md §6, Flow step 4).
// @unchecked Sendable: all state lives on `queue`, where Network.framework calls back.
final class PairingSession: @unchecked Sendable {
    enum Update: Sendable {
        case phase(PadPairing.Phase)
        case saved(PairingRecord)
        case saveFailed
    }

    private let queue = DispatchQueue(label: "co.sharepad.ipad.pairing")
    private let log = Logger(subsystem: "co.sharepad.ipad", category: "pairing")
    private let identity: Hello
    private let store: PairingStore
    private let onUpdate: @MainActor @Sendable (Update) -> Void
    private var pairing = PadPairing()
    private var browser: WireBrowser?
    private var endpoints: [String: NWEndpoint] = [:]
    private var connection: WireConnection?

    init(identity: Hello, store: PairingStore,
         onUpdate: @escaping @MainActor @Sendable (Update) -> Void) {
        self.identity = identity
        self.store = store
        self.onUpdate = onUpdate
    }

    func start(_ code: PairingCode) {
        queue.async { [self] in reduce(.start(code)) }
    }

    func cancel() {
        queue.async { [self] in reduce(.cancel) }
    }

    private func reduce(_ event: PadPairing.Event) {
        perform(pairing.reduce(event))
        report(.phase(pairing.phase))
    }

    private func report(_ update: Update) {
        let onUpdate = onUpdate
        Task { @MainActor in onUpdate(update) }
    }

    private func perform(_ effects: [PadPairing.Effect]) {
        for effect in effects {
            switch effect {
            case .startBrowsing:
                startBrowsing()
            case .stopBrowsing:
                browser?.cancel()
                browser = nil
            case let .connect(name, code):
                connect(to: name, code: code)
            case let .sendCredentials(code):
                sendCredentials(code)
            case let .save(record):
                guard save(record) else { return }
            case let .sendStored(pairingID):
                connection?.send(.stored(pairingID: pairingID))
            case .closeConnection:
                connection?.cancel()
                connection = nil
            case let .scheduleTimeout(attempt, delay):
                queue.asyncAfter(deadline: .now() + delay) { [weak self] in
                    self?.reduce(.timedOut(attempt: attempt))
                }
            }
        }
    }

    private func sendCredentials(_ code: PairingCode) {
        guard let connection, let exporter = connection.linkExporter() else {
            reduce(.connectionFailed)
            return
        }
        connection.send(.authenticate(.pairing(code: code, exporter: exporter)))
        connection.send(.hello(identity))
    }

    private func save(_ record: PairingRecord) -> Bool {
        do {
            try store.savePairing(record)
            report(.saved(record))
            return true
        } catch {
            log.error("could not save the pairing: \(String(describing: error))")
            connection?.cancel()
            connection = nil
            _ = pairing.reduce(.cancel)
            report(.saveFailed)
            return false
        }
    }

    private func startBrowsing() {
        browser?.cancel()
        let browser = WireBrowser()
        browser.onResults = { [weak self] results in
            guard let self else { return }
            endpoints = Dictionary(
                results.map { ($0.serviceName, $0.endpoint) },
                uniquingKeysWith: { first, _ in first }
            )
            reduce(.found(results.map(\.serviceName)))
        }
        browser.start(queue: queue)
        self.browser = browser
    }

    private func connect(to name: String, code: PairingCode) {
        guard let endpoint = endpoints[name] else {
            reduce(.connectionFailed)
            return
        }
        let connection = WireConnection.outbound(
            to: endpoint,
            security: .pairing(code),
            queue: queue
        )
        self.connection = connection
        connection.onEvent = { [weak self, weak connection] event in
            guard let self, let connection, connection === self.connection else { return }
            switch event {
            case .ready:
                reduce(.connectionReady)
            case let .message(.hello(hello)):
                reduce(.helloReceived(hello))
            case .failed, .waiting, .cancelled:
                self.connection = nil
                connection.cancel()
                reduce(.connectionFailed)
            case .message:
                break
            }
        }
        connection.onPairingMessage = { [weak self, weak connection] message in
            guard let self, let connection, connection === self.connection,
                  case let .grant(grant) = message else { return }
            reduce(.grantReceived(grant, at: Date().timeIntervalSince1970))
        }
        connection.start()
    }
}
