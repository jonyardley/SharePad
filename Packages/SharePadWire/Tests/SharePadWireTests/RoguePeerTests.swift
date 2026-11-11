import Foundation
import Network
@testable import SharePadWire
import XCTest

final class RoguePeerTests: XCTestCase {
    private enum Rogue {
        case junkThenClose
        case junkThenHold
        case resetAtOnce
        case silent
        case refused
    }

    private enum Seen: Equatable {
        case ready
        case tls
        case waitingPOSIX
        case failedOther
        case nothing
    }

    private final class Box: @unchecked Sendable {
        private let lock = NSLock()
        private var value: Seen?
        private var kept: [NWConnection] = []

        func settle(_ seen: Seen, _ expectation: XCTestExpectation) {
            lock.withLock {
                guard value == nil else { return }
                value = seen
                expectation.fulfill()
            }
        }

        func keep(_ connection: NWConnection) {
            lock.withLock { kept.append(connection) }
        }

        var seen: Seen? {
            lock.withLock { value }
        }

        func cancelAll() {
            lock.withLock { kept.forEach { $0.cancel() } }
        }
    }

    private let queue = DispatchQueue(label: "rogue-peer-tests")

    private func listen(_ rogue: Rogue, keeping box: Box) throws -> NWListener {
        let listener = try NWListener(using: .tcp, on: .any)
        let queue = queue
        listener.newConnectionHandler = { connection in
            box.keep(connection)
            connection.start(queue: queue)
            let junk = Data("junk".utf8)
            switch rogue {
            case .junkThenClose:
                // Closing before the ClientHello lands can reset instead (54, a POSIX wait).
                connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { _, _, _, _ in
                    connection.send(content: junk, completion: .contentProcessed { _ in
                        connection.cancel()
                    })
                }
            case .junkThenHold:
                connection.send(content: junk, completion: .idempotent)
            case .resetAtOnce:
                connection.cancel()
            case .silent, .refused:
                break
            }
        }
        let ready = expectation(description: "listening")
        listener.stateUpdateHandler = { if case .ready = $0 { ready.fulfill() } }
        listener.start(queue: queue)
        wait(for: [ready], timeout: 5)
        return listener
    }

    private func dial(_ rogue: Rogue, waiting seconds: TimeInterval = 2) throws -> Seen {
        let peer = Box()
        let listener = try listen(rogue, keeping: peer)
        defer {
            peer.cancelAll()
            listener.cancel()
        }
        let port = try XCTUnwrap(listener.port)
        if rogue == .refused {
            let closed = expectation(description: "closed")
            listener.stateUpdateHandler = { if case .cancelled = $0 { closed.fulfill() } }
            listener.cancel()
            wait(for: [closed], timeout: 5)
        }

        let record = PairingRecord(
            peerID: UUID(),
            peerName: "Studio",
            pairingID: UUID(),
            secret: .generate(),
            pairedAt: 1
        )
        let client = WireConnection.outbound(
            to: .hostPort(host: "127.0.0.1", port: port),
            security: .paired(record),
            queue: queue
        )
        defer { client.cancel() }
        let settled = expectation(description: "settled")
        let outcome = Box()
        client.onEvent = { event in
            switch event {
            case .ready:
                outcome.settle(.ready, settled)
            case let .waiting(error) where error.isLinkAuthenticationFailure,
                 let .failed(error?) where error.isLinkAuthenticationFailure:
                outcome.settle(.tls, settled)
            case let .waiting(error):
                if case .posix = error { outcome.settle(.waitingPOSIX, settled) }
            case .failed:
                outcome.settle(.failedOther, settled)
            case .cancelled, .message:
                break
            }
        }
        client.start()
        _ = XCTWaiter.wait(for: [settled], timeout: seconds)
        return outcome.seen ?? .nothing
    }

    // StreamSender counts only `.tls`; a POSIX `.waiting` or silence waits out
    // SenderLink.connectTimeout (specs/wireless-pairing-ui.md, key decision 8).
    func testJunkThenACloseFailsTLS() throws {
        XCTAssertEqual(try dial(.junkThenClose), .tls)
    }

    func testAResetOrARefusalIsAPOSIXWaitNotATLSFailure() throws {
        XCTAssertEqual(try dial(.resetAtOnce), .waitingPOSIX)
        XCTAssertEqual(try dial(.refused), .waitingPOSIX)
    }

    func testAPeerThatNeverCompletesARecordJustStalls() throws {
        XCTAssertEqual(try dial(.silent), .nothing)
        XCTAssertEqual(try dial(.junkThenHold), .nothing)
    }
}
