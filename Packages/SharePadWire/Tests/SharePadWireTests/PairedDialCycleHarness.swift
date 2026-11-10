import Foundation
@testable import SharePadWire
import XCTest

func pairing(_ name: String, peerID: UUID = UUID()) -> PairingRecord {
    PairingRecord(
        peerID: peerID,
        peerName: name,
        pairingID: UUID(),
        secret: .generate(),
        pairedAt: 10
    )
}

struct Dialler {
    var link: SenderLink
    var cycle = PairedDialCycle()
    var counted: [UUID] = []
    var settles: [Int] = []
    var attempt = 0

    init(lastPeer: String? = nil) {
        link = SenderLink(lastPeer: lastPeer)
    }

    var dialling: String? {
        link.phase.dialling
    }

    @discardableResult
    mutating func send(_ event: SenderLink.Event) -> [SenderLink.Effect] {
        let before = link.phase
        let effects = link.reduce(event)
        apply(cycle.reduce(.linkMoved(was: before, now: link.phase)))
        for case let .scheduleConnectTimeout(attempt, _) in effects {
            self.attempt = attempt
        }
        return effects
    }

    mutating func apply(_ effects: [PairedDialCycle.Effect]) {
        for effect in effects {
            switch effect {
            case let .countFailure(macID):
                counted.append(macID)
            case let .scheduleSettle(token, after):
                XCTAssertEqual(after, SenderLink.connectTimeout)
                settles.append(token)
            }
        }
    }

    mutating func browse(_ services: [PairedService]) {
        apply(cycle.reduce(.advertised(services)))
        send(.found(cycle.dialable))
    }

    mutating func failTLS() {
        apply(cycle.reduce(.handshakeFailed(during: link.phase)))
        send(.connectionLost)
    }

    mutating func refuse() {
        send(.connectionLost)
    }

    mutating func timeOut() {
        send(.connectTimedOut(attempt: attempt))
    }

    mutating func retry() {
        send(.retryElapsed)
    }

    mutating func settle(_ token: Int? = nil) {
        guard let token = token ?? settles.last else { return XCTFail("no settle scheduled") }
        apply(cycle.reduce(.settleElapsed(token)))
        send(.found(cycle.dialable))
    }

    mutating func goLive(_ peer: PairingRecord) {
        send(.connectionReady)
        send(.helloReceived(Hello(deviceID: peer.peerID, deviceName: peer.peerName)))
    }
}

func service(_ name: String, _ record: PairingRecord) -> PairedService {
    PairedService(name: name, record: record)
}
