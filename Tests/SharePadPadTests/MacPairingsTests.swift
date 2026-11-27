import Security
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
        XCTAssertEqual(pairings.identity?.deviceID, deviceID)
        XCTAssertEqual(pairings.identity?.deviceName, "Jon’s iPad")
        XCTAssertEqual(pairings.state, .paired)
        XCTAssertFalse(pairings.storeFailed)
        XCTAssertTrue(pairings.canPair)
    }

    func testAnUnreadableInstallIDLeavesNoIdentityAndNoPairing() {
        let pairings = MacPairings(store: NoInstallIDStore(), deviceName: "Jon’s iPad")
        XCTAssertNil(pairings.identity)
        XCTAssertTrue(pairings.storeFailed)
        XCTAssertFalse(pairings.canPair)
        XCTAssertFalse(pairings.screen.canStartPairing)
        XCTAssertEqual(pairings.screen.status, PairingScreenContent.keychainUnreadable)
        XCTAssertEqual(pairings.storeNote, PairingScreenContent.keychainUnreadable)

        pairings.setTypedCode(PairingCode.generate().typed)
        XCTAssertTrue(pairings.isTypedCodeComplete)
        XCTAssertFalse(pairings.pairWithTypedCode())
        XCTAssertFalse(pairings.pairWithScannedCode(PairingCode.generate().typed))
    }

    func testAReadableInstallIDCanPairAndShowsNoNote() throws {
        let (pairings, _) = try pairings([])
        XCTAssertTrue(pairings.screen.canStartPairing)
        XCTAssertNil(pairings.screen.status)
        XCTAssertNil(pairings.storeNote)
    }

    func testASuccessfulWriteKeepsTheNoteWhileTheInstallIDIsUnreadable() throws {
        let studio = record("Studio")
        let store = NoInstallIDStore()
        try store.savePairing(studio)
        let pairings = MacPairings(store: store, deviceName: "Jon’s iPad")

        pairings.forget(id: studio.peerID)

        XCTAssertEqual(try store.loadPairings(), [])
        XCTAssertTrue(pairings.storeFailed)
        XCTAssertEqual(pairings.storeNote, PairingScreenContent.keychainUnreadable)
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

    func testALinkOnlyFillsTheCodeInAndWaitsForATap() throws {
        let (pairings, _) = try pairings([])
        let code = PairingCode.generate()
        pairings.reset(typedCode: code)
        XCTAssertEqual(pairings.typedCode, code.typed)
        XCTAssertTrue(pairings.showsTypedEntry)
        XCTAssertTrue(pairings.isTypedCodeComplete)
        XCTAssertEqual(pairings.phase, .idle)
        XCTAssertEqual(pairings.closeButtonTitle, "Close")
    }
}

private final class NoInstallIDStore: PairingStore {
    private let records = InMemoryPairingStore(deviceID: UUID())

    func loadPairings() throws -> [PairingRecord] {
        try records.loadPairings()
    }

    func savePairing(_ record: PairingRecord) throws {
        try records.savePairing(record)
    }

    func deletePairing(peerID: UUID) throws {
        try records.deletePairing(peerID: peerID)
    }

    func localDeviceID() throws -> UUID {
        throw PairingStoreError.keychain(errSecInteractionNotAllowed)
    }
}
