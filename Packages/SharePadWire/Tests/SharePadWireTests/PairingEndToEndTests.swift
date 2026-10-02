import Foundation
import Network
@testable import SharePadWire
import XCTest

// @unchecked: all state is touched only on `queue`.
private final class MacShell: @unchecked Sendable {
    let queue: DispatchQueue
    let hello = Hello(deviceID: UUID(), deviceName: "Jon’s MacBook Pro")
    var window = PairingWindow()
    var book = PairingBook()
    var listener: WireListener?
    var connections: [ConnectionID: WireConnection] = [:]
    var gates: [ConnectionID: LinkGate] = [:]
    var admitted: [LinkAuthentication.Peer] = []
    var closed: [ConnectionID: String] = [:]
    var nextID = 0

    init(queue: DispatchQueue) {
        self.queue = queue
    }

    func listen(onReady: @escaping @Sendable (UInt16) -> Void) throws {
        listener?.cancel()
        let listener = try WireListener(
            serviceName: nil,
            security: .server(pairingCode: window.acceptingCode, paired: book.records),
            queue: queue
        )
        self.listener = listener
        listener.onStateChange = { [weak listener] state in
            if case .ready = state, let port = listener?.port { onReady(port) }
        }
        listener.onConnection = { [weak self] connection in self?.accept(connection) }
        listener.start()
    }

    private func accept(_ connection: WireConnection) {
        nextID += 1
        let id = nextID
        connections[id] = connection
        gates[id] = LinkGate()
        connection.onEvent = { [weak self] event in
            switch event {
            case .ready: connection.send(.hello(self?.hello ?? Hello(
                    deviceID: UUID(),
                    deviceName: ""
                )))
            case let .message(.hello(hello)): self?.gate(id, .helloReceived(hello))
            case .message: self?.gate(id, .streamMessage)
            case .failed, .cancelled: self?.apply(self?.window.reduce(.connectionClosed(id)) ?? [])
            case .waiting: break
            }
        }
        connection.onPairingMessage = { [weak self] message in self?.pairingMessage(
            message,
            from: id
        ) }
        connection.start()
    }

    private func pairingMessage(_ message: PairingMessage, from id: ConnectionID) {
        switch message {
        case let .authenticate(credential):
            let exporter = connections[id]?.linkExporter()
            let peer = LinkAuthentication.verify(
                credential,
                exporter: exporter,
                pairingCode: window.acceptingCode,
                paired: book.records
            )
            gate(id, .credentialChecked(peer))
        case let .stored(pairingID):
            guard gate(id, .pairingMessage) else { return }
            apply(window.reduce(.stored(id, pairingID: pairingID, at: 2)))
        case .grant:
            close(id, "grant from an iPad")
        }
    }

    @discardableResult
    private func gate(_ id: ConnectionID, _ event: LinkGate.Event) -> Bool {
        guard var gate = gates[id] else { return false }
        let decision = gate.reduce(event)
        gates[id] = gate
        switch decision {
        case .wait:
            return false
        case .pass:
            return true
        case let .admitHello(peer, hello):
            admitted.append(peer)
            if case .pairing = peer {
                apply(window.reduce(.pairingHello(id, hello, at: 1)))
            }
            return true
        case let .close(reason):
            close(id, "\(reason)")
            return false
        }
    }

    func apply(_ effects: [PairingWindow.Effect]) {
        for effect in effects {
            switch effect {
            case .acceptPairing, .stopAcceptingPairing:
                break
            case let .sendGrant(id, grant):
                connections[id]?.send(.grant(grant))
            case let .store(record):
                _ = book.reduce(.paired(record))
            case let .close(id, reason):
                close(id, "\(reason)")
            }
        }
    }

    private func close(_ id: ConnectionID, _ reason: String) {
        closed[id] = reason
        connections[id]?.cancel()
    }

    func stop() {
        listener?.cancel()
        connections.values.forEach { $0.cancel() }
    }
}

// @unchecked: all state is touched only on `queue`.
private final class PadShell: @unchecked Sendable {
    let queue: DispatchQueue
    let hello = Hello(deviceID: UUID(), deviceName: "Jon’s iPad")
    let store = InMemoryPairingStore()
    var pairing = PadPairing()
    var connection: WireConnection?
    var port: UInt16 = 0
    var linkReady = false

    init(queue: DispatchQueue) {
        self.queue = queue
    }

    func pair(with code: PairingCode, port: UInt16) {
        self.port = port
        apply(pairing.reduce(.start(code)))
        apply(pairing.reduce(.found(["Mac"])))
    }

    func connectPaired(_ record: PairingRecord, port: UInt16) {
        let connection = WireConnection.outbound(
            to: endpoint(port),
            security: .paired(record),
            queue: queue
        )
        self.connection = connection
        connection.onEvent = { [weak self] event in
            guard let self, case .ready = event,
                  let exporter = connection.linkExporter() else { return }
            connection.send(.authenticate(.paired(record, exporter: exporter)))
            connection.send(.hello(hello))
            linkReady = true
        }
        connection.start()
    }

    private func endpoint(_ port: UInt16) -> NWEndpoint {
        .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port) ?? .any)
    }

    private func apply(_ effects: [PadPairing.Effect]) {
        for effect in effects {
            switch effect {
            case .startBrowsing, .stopBrowsing, .scheduleTimeout:
                break
            case let .connect(_, code):
                connect(code)
            case let .sendCredentials(code):
                guard let exporter = connection?.linkExporter() else { return }
                connection?.send(.authenticate(.pairing(code: code, exporter: exporter)))
                connection?.send(.hello(hello))
            case let .save(record):
                try? store.savePairing(record)
            case let .sendStored(pairingID):
                connection?.send(.stored(pairingID: pairingID))
            case .closeConnection:
                connection?.cancel()
            }
        }
    }

    private func connect(_ code: PairingCode) {
        let connection = WireConnection.outbound(
            to: endpoint(port),
            security: .pairing(code),
            queue: queue
        )
        self.connection = connection
        connection.onEvent = { [weak self] event in
            guard let self else { return }
            switch event {
            case .ready: apply(pairing.reduce(.connectionReady))
            case let .message(.hello(hello)): apply(pairing.reduce(.helloReceived(hello)))
            case .failed, .waiting: apply(pairing.reduce(.connectionFailed))
            case .message, .cancelled: break
            }
        }
        connection.onPairingMessage = { [weak self] message in
            guard let self, case let .grant(grant) = message else { return }
            apply(pairing.reduce(.grantReceived(grant, at: 1)))
        }
        connection.start()
    }
}

final class PairingEndToEndTests: XCTestCase {
    private let queue = DispatchQueue(label: "pairing-end-to-end")

    private func waitUntil(_ description: String, _ condition: @escaping @Sendable () -> Bool) {
        let met = expectation(description: description)
        let queue = queue
        @Sendable func poll() {
            if condition() {
                met.fulfill()
            } else {
                queue.asyncAfter(deadline: .now() + 0.02, execute: poll)
            }
        }
        queue.async(execute: poll)
        wait(for: [met], timeout: 5)
    }

    private func listen(_ mac: MacShell) throws -> UInt16 {
        let ready = expectation(description: "listening")
        let port = PortBox()
        try queue.sync {
            try mac.listen { value in
                port.value = value
                ready.fulfill()
            }
        }
        wait(for: [ready], timeout: 5)
        return port.value
    }

    private final class PortBox: @unchecked Sendable {
        var value: UInt16 = 0
    }

    func testAnIPadPairsWithTheCodeThenStreamsOnTheNewSecret() throws {
        let mac = MacShell(queue: queue)
        let pad = PadShell(queue: queue)
        defer { queue.sync { mac.stop() } }

        let offer = PairingOffer.generate(at: 0)
        queue.sync { mac.apply(mac.window.reduce(.open(offer))) }
        let pairingPort = try listen(mac)
        queue.sync { pad.pair(with: offer.code, port: pairingPort) }

        waitUntil("both sides stored the pairing") {
            mac.book.records.count == 1 && (try? pad.store.loadPairings().count) == 1
        }
        let (macRecord, padRecord) = try queue.sync {
            try (XCTUnwrap(mac.book.records.first), XCTUnwrap(pad.store.loadPairings().first))
        }
        XCTAssertEqual(macRecord.peerID, pad.hello.deviceID)
        XCTAssertEqual(macRecord.peerName, pad.hello.deviceName)
        XCTAssertEqual(padRecord.peerID, mac.hello.deviceID)
        XCTAssertEqual(padRecord.pairingID, macRecord.pairingID)
        XCTAssertEqual(padRecord.secret, macRecord.secret)
        XCTAssertEqual(padRecord.secret, offer.secret)
        XCTAssertNil(queue.sync { mac.window.acceptingCode })

        let linkPort = try listen(mac)
        queue.sync { pad.connectPaired(padRecord, port: linkPort) }
        waitUntil("the Mac admitted the paired iPad") {
            mac.admitted.contains(.paired(macRecord))
        }

        let stranger = PadShell(queue: queue)
        queue.sync { stranger.pair(with: offer.code, port: linkPort) }
        waitUntil("the spent code is refused") {
            if case .failed = stranger.pairing.phase { return true }
            if case .searching = stranger.pairing.phase { return true }
            return false
        }
        XCTAssertEqual(queue.sync { mac.book.records.count }, 1)
    }
}
