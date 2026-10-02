import Foundation
@testable import SharePadWire
import XCTest

final class PairingMessageTests: XCTestCase {
    private func roundTrip(_ message: PairingMessage) throws -> PairingMessage {
        let data = message.encoded()
        let (typeCode, length) = try WireMessage.header(data.prefix(WireService.headerLength))
        XCTAssertTrue(PairingMessage.handles(typeCode))
        XCTAssertFalse(PairingMessage.handles(WireMessage.requestKeyframe.encoded()[0]))
        return try PairingMessage.decode(
            typeCode: typeCode,
            payload: data.dropFirst(WireService.headerLength).prefix(length)
        )
    }

    func testMessagesRoundTrip() throws {
        let messages: [PairingMessage] = [
            .authenticate(.pairing(proof: Data(repeating: 1, count: 32))),
            .authenticate(.paired(pairingID: UUID(), proof: Data(repeating: 2, count: 32))),
            .grant(PairingGrant(pairingID: UUID(), secret: LinkSecret.generate())),
            .stored(pairingID: UUID()),
        ]
        for message in messages {
            XCTAssertEqual(try roundTrip(message), message)
        }
    }

    func testTypeCodesDoNotCollideWithStreamMessages() {
        for code in UInt8(1) ... 8 {
            XCTAssertFalse(PairingMessage.handles(code))
        }
    }

    func testMalformedPayloadsAreRejected() {
        let cases: [(UInt8, Data)] = [
            (16, Data([0]) + Data(repeating: 0, count: 31)),
            (16, Data([1]) + Data(repeating: 0, count: 47)),
            (16, Data([9]) + Data(repeating: 0, count: 32)),
            (16, Data([0]) + Data(repeating: 0, count: 33)),
            (17, Data(repeating: 0, count: 16 + 31)),
            (17, Data(repeating: 0, count: 16 + 33)),
            (18, Data(repeating: 0, count: 15)),
            (18, Data(repeating: 0, count: 17)),
        ]
        for (typeCode, payload) in cases {
            XCTAssertThrowsError(try PairingMessage.decode(typeCode: typeCode, payload: payload))
        }
        XCTAssertThrowsError(try PairingMessage.decode(typeCode: 3, payload: Data()))
    }

    func testGrantDescriptionHidesTheSecret() {
        let grant = PairingGrant(pairingID: UUID(), secret: LinkSecret.generate())
        let hex = grant.secret.bytes.map { String(format: "%02x", $0) }.joined()
        XCTAssertFalse(String(describing: PairingMessage.grant(grant)).contains(hex))
    }
}

final class LinkProofTests: XCTestCase {
    private let exporter = Data((0 ..< 32).map { UInt8($0) })
    private let code = PairingCode.generate()

    private func record(_ secret: LinkSecret = .generate()) -> PairingRecord {
        PairingRecord(
            peerID: UUID(),
            peerName: "Jon’s iPad",
            pairingID: UUID(),
            secret: secret,
            pairedAt: 1
        )
    }

    func testAPairingProofVerifiesAgainstTheOpenCode() {
        let credential = LinkCredential.pairing(code: code, exporter: exporter)
        XCTAssertEqual(
            LinkAuthentication.verify(
                credential,
                exporter: exporter,
                pairingCode: code,
                paired: []
            ),
            .pairing
        )
    }

    func testAPairingProofFailsWithoutAnOpenCodeOrWithAnotherCode() {
        let credential = LinkCredential.pairing(code: code, exporter: exporter)
        XCTAssertNil(LinkAuthentication.verify(
            credential,
            exporter: exporter,
            pairingCode: nil,
            paired: []
        ))
        XCTAssertNil(LinkAuthentication.verify(
            credential, exporter: exporter, pairingCode: .generate(), paired: []
        ))
    }

    func testALinkProofResolvesToItsPairing() {
        let mine = record()
        let other = record()
        let credential = LinkCredential.paired(mine, exporter: exporter)
        XCTAssertEqual(
            LinkAuthentication.verify(
                credential,
                exporter: exporter,
                pairingCode: code,
                paired: [other, mine]
            ),
            .paired(mine)
        )
    }

    func testAProofFromAnotherSessionIsRejected() {
        let mine = record()
        let credential = LinkCredential.paired(mine, exporter: exporter)
        var otherSession = exporter
        otherSession[0] ^= 1
        XCTAssertNil(LinkAuthentication.verify(
            credential,
            exporter: otherSession,
            pairingCode: nil,
            paired: [mine]
        ))
    }

    func testAPairedIPadCannotClaimAnotherPairing() {
        let mine = record()
        let victim = record()
        guard case let .paired(_, proof) = LinkCredential.paired(mine, exporter: exporter) else {
            return XCTFail("expected a paired credential")
        }
        let forged = LinkCredential.paired(pairingID: victim.pairingID, proof: proof)
        XCTAssertNil(LinkAuthentication.verify(
            forged,
            exporter: exporter,
            pairingCode: nil,
            paired: [mine, victim]
        ))
    }

    func testAPairingProofCannotPassAsALinkProofOrTheReverse() {
        let mine = record()
        guard case let .pairing(pairingProof) = LinkCredential.pairing(
            code: code,
            exporter: exporter
        ),
            case let .paired(_, linkProof) = LinkCredential.paired(mine, exporter: exporter)
        else {
            return XCTFail("unexpected credential shape")
        }
        XCTAssertNil(LinkAuthentication.verify(
            .paired(pairingID: mine.pairingID, proof: pairingProof),
            exporter: exporter, pairingCode: code, paired: [mine]
        ))
        XCTAssertNil(LinkAuthentication.verify(
            .pairing(proof: linkProof), exporter: exporter, pairingCode: code, paired: [mine]
        ))
    }

    func testAForgottenPairingNoLongerVerifies() {
        let mine = record()
        let credential = LinkCredential.paired(mine, exporter: exporter)
        XCTAssertNil(LinkAuthentication.verify(
            credential,
            exporter: exporter,
            pairingCode: nil,
            paired: []
        ))
    }
}

final class LinkGateTests: XCTestCase {
    private let pad = Hello(deviceID: UUID(), deviceName: "Jon’s iPad")

    private func record(for hello: Hello) -> PairingRecord {
        PairingRecord(
            peerID: hello.deviceID,
            peerName: hello.deviceName,
            pairingID: UUID(),
            secret: .generate(),
            pairedAt: 1
        )
    }

    func testNothingPassesBeforeACredential() {
        var gate = LinkGate()
        XCTAssertEqual(gate.reduce(.helloReceived(pad)), .close(.unauthenticated))
        XCTAssertEqual(gate.phase, .closed)
        XCTAssertEqual(gate.reduce(.streamMessage), .close(.unauthenticated))

        var other = LinkGate()
        XCTAssertEqual(other.reduce(.streamMessage), .close(.unauthenticated))
        var third = LinkGate()
        XCTAssertEqual(third.reduce(.pairingMessage), .close(.unauthenticated))
    }

    func testABadCredentialCloses() {
        var gate = LinkGate()
        XCTAssertEqual(gate.reduce(.credentialChecked(nil)), .close(.badCredential))
        XCTAssertEqual(gate.reduce(.credentialChecked(.pairing)), .close(.badCredential))
    }

    func testAPairedIPadIsAdmittedOnlyUnderItsOwnID() {
        let paired = record(for: pad)
        var gate = LinkGate()
        XCTAssertEqual(gate.reduce(.credentialChecked(.paired(paired))), .wait)
        XCTAssertEqual(gate.reduce(.streamMessage), .close(.unauthenticated))

        var admitted = LinkGate()
        _ = admitted.reduce(.credentialChecked(.paired(paired)))
        XCTAssertEqual(admitted.reduce(.helloReceived(pad)), .admitHello(.paired(paired), pad))
        XCTAssertEqual(admitted.reduce(.streamMessage), .pass)
        XCTAssertEqual(admitted.reduce(.helloReceived(pad)), .pass)
        XCTAssertEqual(admitted.reduce(.pairingMessage), .close(.notPairing))

        var spoofed = LinkGate()
        _ = spoofed.reduce(.credentialChecked(.paired(paired)))
        let impostor = Hello(deviceID: UUID(), deviceName: pad.deviceName)
        XCTAssertEqual(spoofed.reduce(.helloReceived(impostor)), .close(.identityMismatch))
    }

    func testAChangedIDMidLinkCloses() {
        let paired = record(for: pad)
        var gate = LinkGate()
        _ = gate.reduce(.credentialChecked(.paired(paired)))
        _ = gate.reduce(.helloReceived(pad))
        XCTAssertEqual(
            gate.reduce(.helloReceived(Hello(deviceID: UUID(), deviceName: "x"))),
            .close(.identityMismatch)
        )
    }

    func testAPairingPeerMayOnlyPair() {
        var gate = LinkGate()
        XCTAssertEqual(gate.reduce(.credentialChecked(.pairing)), .wait)
        XCTAssertEqual(gate.reduce(.pairingMessage), .close(.unauthenticated))

        var pairing = LinkGate()
        _ = pairing.reduce(.credentialChecked(.pairing))
        XCTAssertEqual(pairing.reduce(.helloReceived(pad)), .admitHello(.pairing, pad))
        XCTAssertEqual(pairing.reduce(.pairingMessage), .pass)
        XCTAssertEqual(pairing.reduce(.streamMessage), .close(.notPaired))
    }
}
