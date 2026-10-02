@testable import SharePadPad
import SharePadWire
import XCTest

@MainActor
final class MacPairingsTests: XCTestCase {
    private let deviceID = UUID()

    private func record(_ name: String) -> PairingRecord {
        PairingRecord(
            peerID: UUID(),
            peerName: name,
            pairingID: UUID(),
            secret: .generate(),
            pairedAt: 1
        )
    }

    private func pairings(_ records: [PairingRecord]) throws -> (MacPairings, PairingStore) {
        let store = InMemoryPairingStore(deviceID: deviceID)
        for record in records {
            try store.savePairing(record)
        }
        return (MacPairings(store: store, deviceName: "Jon’s iPad"), store)
    }

    func testLoadsPairingsAndTheKeychainInstallID() throws {
        let studio = record("Studio")
        let (pairings, _) = try pairings([studio])
        XCTAssertEqual(pairings.macs, [studio])
        XCTAssertEqual(pairings.identity.deviceID, deviceID)
        XCTAssertEqual(pairings.identity.deviceName, "Jon’s iPad")
        XCTAssertEqual(pairings.state, .paired)
        XCTAssertFalse(pairings.storeFailed)
    }

    func testNothingPairedIsUnpaired() throws {
        let (pairings, _) = try pairings([])
        XCTAssertEqual(pairings.state, .unpaired)
        XCTAssertEqual(pairings.pairButtonTitle, "Pair with your Mac…")
    }

    func testForgetRemovesTheMacAndHandsTheLinkTheNewList() throws {
        let studio = record("Studio")
        let office = record("Office")
        let (pairings, store) = try pairings([studio, office])
        var handed: [[PairingRecord]] = []
        pairings.onChange = { handed.append($0) }

        pairings.forget(id: studio.peerID)

        XCTAssertEqual(pairings.macs.map(\.peerName), ["Office"])
        XCTAssertEqual(try store.loadPairings().map(\.peerID), [office.peerID])
        XCTAssertEqual(handed.last?.map(\.peerID), [office.peerID])
    }

    func testThreeFailedHandshakesInARowMarkTheMacNotPaired() throws {
        let studio = record("Studio")
        let (pairings, _) = try pairings([studio])
        pairings.linkEvent(.handshakeFailed(macID: studio.peerID))
        pairings.linkEvent(.handshakeFailed(macID: studio.peerID))
        XCTAssertEqual(pairings.state, .paired)
        pairings.linkEvent(.handshakeFailed(macID: studio.peerID))
        XCTAssertEqual(pairings.state, .broken("Studio"))

        pairings.linkEvent(.connected(macID: studio.peerID))
        XCTAssertEqual(pairings.state, .paired)
    }

    func testAConnectionRecordsWhenTheMacWasLastUsed() throws {
        let studio = record("Studio")
        let (pairings, store) = try pairings([studio])
        pairings.linkEvent(.connected(macID: studio.peerID))
        XCTAssertNotNil(pairings.macs.first?.lastConnectedAt)
        XCTAssertNotNil(try store.loadPairings().first?.lastConnectedAt)
    }

    func testTypedCodeIsFormattedAndCompleteOnlyAtFullLength() throws {
        let (pairings, _) = try pairings([])
        pairings.setTypedCode("k7qm4x")
        XCTAssertEqual(pairings.typedCode, "K7QM-4X")
        XCTAssertFalse(pairings.isTypedCodeComplete)
        pairings.setTypedCode(PairingCode.generate().typed)
        XCTAssertTrue(pairings.isTypedCodeComplete)
    }

    func testAnUnrelatedScannedCodeIsNotTakenAsAPairingCode() throws {
        let (pairings, _) = try pairings([])
        XCTAssertFalse(pairings.pairWithScannedCode("https://example.com"))
        XCTAssertEqual(pairings.phase, .idle)
    }
}
