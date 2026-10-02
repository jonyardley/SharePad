import Foundation
import Network
@testable import SharePadWire
import XCTest

private final class Recorder: @unchecked Sendable {
    private let lock = NSLock()
    private var connections: [WireConnection] = []
    private var stream: [WireMessage] = []
    private var pairing: [PairingMessage] = []

    func keep(_ connection: WireConnection) {
        lock.withLock { connections.append(connection) }
    }

    func record(_ message: WireMessage) {
        lock.withLock { stream.append(message) }
    }

    func record(_ message: PairingMessage) {
        lock.withLock { pairing.append(message) }
    }

    var server: WireConnection? {
        lock.withLock { connections.first }
    }

    var streamMessages: [WireMessage] {
        lock.withLock { stream }
    }

    var pairingMessages: [PairingMessage] {
        lock.withLock { pairing }
    }
}

private func defaultSuiteParameters(key: LinkSecret) -> NWParameters {
    let tls = NWProtocolTLS.Options()
    sec_protocol_options_add_pre_shared_key(
        tls.securityProtocolOptions,
        key.bytes.withUnsafeBytes { DispatchData(bytes: $0) } as __DispatchData,
        Data("test".utf8).withUnsafeBytes { DispatchData(bytes: $0) } as __DispatchData
    )
    return NWParameters(tls: tls, tcp: .init())
}

final class SecureLinkTests: XCTestCase {
    private let queue = DispatchQueue(label: "secure-link-tests")
    private var listener: WireListener?
    private var client: WireConnection?
    private let recorder = Recorder()

    override func tearDown() {
        client?.cancel()
        recorder.server?.cancel()
        listener?.cancel()
        super.tearDown()
    }

    private func record(_ secret: LinkSecret = .generate()) -> PairingRecord {
        PairingRecord(
            peerID: UUID(),
            peerName: "Jon’s iPad",
            pairingID: UUID(),
            secret: secret,
            pairedAt: 1
        )
    }

    private func listen(_ security: LinkSecurity) throws -> UInt16 {
        let listener = try WireListener(serviceName: nil, security: security, queue: queue)
        self.listener = listener
        let ready = expectation(description: "listening")
        let recorder = recorder
        listener.onStateChange = { state in
            if case .ready = state { ready.fulfill() }
        }
        listener.onConnection = { connection in
            recorder.keep(connection)
            connection.onEvent = { event in
                if case let .message(message) = event { recorder.record(message) }
            }
            connection.onPairingMessage = { recorder.record($0) }
            connection.start()
        }
        listener.start()
        wait(for: [ready], timeout: 5)
        return try XCTUnwrap(listener.port)
    }

    private enum Outcome: Equatable {
        case ready
        case rejected(authentication: Bool)
    }

    private func connect(port: UInt16, security: LinkSecurity) -> Outcome? {
        let endpoint = NWEndpoint.hostPort(
            host: "127.0.0.1",
            port: NWEndpoint.Port(rawValue: port) ?? .any
        )
        let client = WireConnection.outbound(to: endpoint, security: security, queue: queue)
        self.client = client
        let settled = expectation(description: "settled")
        let box = OutcomeBox()
        client.onEvent = { event in
            switch event {
            case .ready:
                box.settle(.ready, settled)
            case let .waiting(error), let .failed(error?):
                box.settle(.rejected(authentication: error.isLinkAuthenticationFailure), settled)
            case .failed(nil):
                box.settle(.rejected(authentication: false), settled)
            case .cancelled, .message:
                break
            }
        }
        client.start()
        wait(for: [settled], timeout: 5)
        return box.outcome
    }

    private final class OutcomeBox: @unchecked Sendable {
        private let lock = NSLock()
        private var value: Outcome?

        func settle(_ outcome: Outcome, _ expectation: XCTestExpectation) {
            lock.withLock {
                guard value == nil else { return }
                value = outcome
                expectation.fulfill()
            }
        }

        var outcome: Outcome? {
            lock.withLock { value }
        }
    }

    // Open question 3: Network.framework only does PSK over TLS 1.2, and its default
    // suite (TLS_PSK_WITH_AES_128_GCM_SHA256) has no forward secrecy. We pin ECDHE-PSK.
    func testAPairedLinkNegotiatesForwardSecretTLS() throws {
        let paired = record()
        let port = try listen(.server(pairingCode: nil, paired: [record(), paired]))
        XCTAssertEqual(connect(port: port, security: .paired(paired)), .ready)
        let tls = try XCTUnwrap(client?.negotiatedTLS)
        XCTAssertEqual(tls.version, tls_protocol_version_t.TLSv12.rawValue)
        XCTAssertEqual(tls.suite, LinkSecurity.cipherSuite)
        XCTAssertEqual(tls.suite, 0xCCAC)
    }

    func testTheDefaultPSKSuiteHasNoForwardSecrecy() throws {
        let key = LinkSecret.generate()
        let listener = try NWListener(using: defaultSuiteParameters(key: key), on: .any)
        let ready = expectation(description: "listening")
        let queue = queue
        listener.newConnectionHandler = { $0.start(queue: queue) }
        listener.stateUpdateHandler = { if case .ready = $0 { ready.fulfill() } }
        listener.start(queue: queue)
        defer { listener.cancel() }
        wait(for: [ready], timeout: 5)
        let port = try XCTUnwrap(listener.port)
        let connection = NWConnection(
            to: .hostPort(host: "127.0.0.1", port: port),
            using: defaultSuiteParameters(key: key)
        )
        let connected = expectation(description: "connected")
        connection.stateUpdateHandler = { if case .ready = $0 { connected.fulfill() } }
        connection.start(queue: queue)
        defer { connection.cancel() }
        wait(for: [connected], timeout: 5)
        let tls = try XCTUnwrap(WireConnection.negotiatedTLS(of: connection))
        XCTAssertEqual(tls.suite, 0x00A8)
    }

    func testAWrongSecretFailsTheHandshake() throws {
        let paired = record()
        let port = try listen(.server(pairingCode: nil, paired: [paired]))
        let imposter = PairingRecord(
            peerID: paired.peerID,
            peerName: paired.peerName,
            pairingID: paired.pairingID,
            secret: .generate(),
            pairedAt: 1
        )
        XCTAssertEqual(
            connect(port: port, security: .paired(imposter)),
            .rejected(authentication: true)
        )
    }

    func testAForgottenPairingFailsTheHandshake() throws {
        let port = try listen(.server(pairingCode: nil, paired: [record()]))
        XCTAssertEqual(
            connect(port: port, security: .paired(record())),
            .rejected(authentication: true)
        )
    }

    func testAPlainConnectionCannotReachASecureListener() throws {
        let port = try listen(.server(pairingCode: nil, paired: [record()]))
        let outcome = connect(port: port, security: .unauthenticated)
        if outcome == .ready {
            client?.send(.hello(Hello(deviceID: UUID(), deviceName: "plain")))
            let quiet = expectation(description: "nothing delivered")
            quiet.isInverted = true
            wait(for: [quiet], timeout: 1)
        }
        XCTAssertTrue(recorder.streamMessages.isEmpty)
    }

    func testAPairingCodeOpensAPairingLinkOnlyWhileOffered() throws {
        let code = PairingCode.generate()
        let port = try listen(.server(pairingCode: code, paired: []))
        XCTAssertEqual(connect(port: port, security: .pairing(code)), .ready)
        client?.cancel()
        XCTAssertEqual(
            connect(port: port, security: .pairing(.generate())),
            .rejected(authentication: true)
        )

        listener?.cancel()
        let closed = try listen(.server(pairingCode: nil, paired: [record()]))
        XCTAssertEqual(
            connect(port: closed, security: .pairing(code)),
            .rejected(authentication: true)
        )
    }

    func testBothEndsExportTheSameSecretAndTheProofVerifies() throws {
        let paired = record()
        let port = try listen(.server(pairingCode: nil, paired: [paired]))
        XCTAssertEqual(connect(port: port, security: .paired(paired)), .ready)
        let clientExporter = try XCTUnwrap(client?.linkExporter())
        XCTAssertEqual(clientExporter.count, LinkAuthentication.exporterLength)

        client?.send(.authenticate(.paired(paired, exporter: clientExporter)))
        client?.send(.hello(Hello(deviceID: paired.peerID, deviceName: paired.peerName)))
        let delivered = expectation(description: "delivered")
        let recorder = recorder
        func poll() {
            if !recorder.pairingMessages.isEmpty, !recorder.streamMessages.isEmpty {
                delivered.fulfill()
            } else {
                queue.asyncAfter(deadline: .now() + 0.05, execute: poll)
            }
        }
        poll()
        wait(for: [delivered], timeout: 5)

        let serverExporter = try XCTUnwrap(recorder.server?.linkExporter())
        XCTAssertEqual(serverExporter, clientExporter)
        guard case let .authenticate(credential) = recorder.pairingMessages.first else {
            return XCTFail("expected a credential")
        }
        XCTAssertEqual(
            LinkAuthentication.verify(
                credential,
                exporter: serverExporter,
                pairingCode: nil,
                paired: [paired]
            ),
            .paired(paired)
        )
    }

    func testAnUnauthenticatedLinkHasNoExporter() throws {
        let listener = try WireListener(serviceName: nil, security: .unauthenticated, queue: queue)
        self.listener = listener
        let ready = expectation(description: "listening")
        listener.onStateChange = { if case .ready = $0 { ready.fulfill() } }
        listener.onConnection = { [recorder] in
            recorder.keep($0)
            $0.start()
        }
        listener.start()
        wait(for: [ready], timeout: 5)
        let port = try XCTUnwrap(listener.port)
        XCTAssertEqual(connect(port: port, security: .unauthenticated), .ready)
        XCTAssertNil(client?.linkExporter())
        XCTAssertNil(client?.negotiatedTLS)
    }

    func testSecurityParametersKeepTheStreamTuning() {
        let parameters = WireParameters.stream(security: .paired(record()))
        XCTAssertTrue(parameters.includePeerToPeer)
        XCTAssertEqual(parameters.serviceClass, .interactiveVideo)
        XCTAssertEqual(
            WireParameters.stream(security: .unauthenticated).serviceClass,
            .interactiveVideo
        )
    }

    func testPSKIdentitiesNeverCarryTheCode() {
        let code = PairingCode.generate()
        let identity = LinkSecurity.pairingIdentity
        XCTAssertFalse(identity.contains(code.bytes))
        let paired = record()
        XCTAssertEqual(
            LinkSecurity.identity(for: paired),
            Data("co.sharepad.link.v1:\(paired.pairingID.uuidString)".utf8)
        )
    }
}
