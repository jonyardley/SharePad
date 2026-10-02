import Foundation
import Security
@testable import SharePadWire
import XCTest

private func sampleRecord(
    peer: UUID = UUID(),
    name: String = "Jon’s iPad",
    lastConnected: TimeInterval? = nil
) -> PairingRecord {
    PairingRecord(
        peerID: peer,
        peerName: name,
        pairingID: UUID(),
        secret: .generate(),
        pairedAt: 1_759_000_000,
        lastConnectedAt: lastConnected
    )
}

private func exerciseContract(
    _ store: some PairingStore,
    file: StaticString = #filePath,
    line: UInt = #line
) throws {
    XCTAssertEqual(try store.loadPairings(), [], file: file, line: line)

    let first = sampleRecord(lastConnected: 1_759_000_100)
    let second = sampleRecord(name: "Studio iPad")
    try store.savePairing(first)
    try store.savePairing(second)
    XCTAssertEqual(
        try Set(store.loadPairings().map(\.pairingID)),
        [first.pairingID, second.pairingID],
        file: file,
        line: line
    )

    let replacement = sampleRecord(peer: first.peerID, name: "Renamed")
    try store.savePairing(replacement)
    let loaded = try store.loadPairings()
    XCTAssertEqual(loaded.count, 2, file: file, line: line)
    XCTAssertEqual(loaded.first { $0.peerID == first.peerID }, replacement, file: file, line: line)
    XCTAssertEqual(loaded.first { $0.peerID == second.peerID }, second, file: file, line: line)

    try store.deletePairing(peerID: first.peerID)
    try store.deletePairing(peerID: UUID())
    XCTAssertEqual(try store.loadPairings(), [second], file: file, line: line)

    let id = try store.localDeviceID()
    XCTAssertEqual(try store.localDeviceID(), id, file: file, line: line)
}

final class PairingStoreTests: XCTestCase {
    func testInMemoryStoreKeepsTheContract() throws {
        try exerciseContract(InMemoryPairingStore())
    }

    func testInMemoryStoreCanStartWithAnID() throws {
        let id = UUID()
        XCTAssertEqual(try InMemoryPairingStore(deviceID: id).localDeviceID(), id)
    }

    func testRecordsSurviveEncoding() throws {
        for original in [sampleRecord(), sampleRecord(lastConnected: 5)] {
            XCTAssertEqual(try PairingRecord.decode(original.encoded()), original)
        }
    }

    func testCorruptRecordsAreRejected() {
        let encoded = sampleRecord().encoded()
        XCTAssertThrowsError(try PairingRecord.decode(encoded.dropLast()))
        XCTAssertThrowsError(try PairingRecord.decode(encoded + Data([0])))
        var wrongVersion = encoded
        wrongVersion[0] = 9
        XCTAssertThrowsError(try PairingRecord.decode(wrongVersion))
    }

    func testRecordDescriptionsHideTheSecret() {
        let sample = sampleRecord()
        let hex = sample.secret.bytes.map { String(format: "%02x", $0) }.joined()
        XCTAssertFalse(String(describing: sample).contains(hex))
        XCTAssertFalse(String(reflecting: sample).contains(hex))
    }

    func testKeychainStoreKeepsTheContract() throws {
        let store = KeychainPairingStore(service: "co.sharepad.wire.tests.\(UUID().uuidString)")
        defer { try? store.removeAll() }
        do {
            _ = try store.loadPairings()
            try store.savePairing(sampleRecord())
            try store.removeAll()
        } catch let PairingStoreError.keychain(status) where Self.unavailable.contains(status) {
            throw XCTSkip("No usable keychain in this environment (OSStatus \(status))")
        }
        try exerciseContract(store)
    }

    func testKeychainItemsAreDeviceOnlyAndNeverSynced() {
        let attributes = KeychainPairingStore(service: "x").baseQuery(kind: .pairing)
        XCTAssertEqual(attributes[kSecAttrSynchronizable as String] as? Bool, false)
        XCTAssertEqual(
            attributes[kSecAttrAccessible as String] as? String,
            kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String
        )
    }

    private static let unavailable: Set<OSStatus> = [
        errSecInteractionNotAllowed, errSecNoSuchKeychain, errSecNotAvailable,
        errSecMissingEntitlement,
    ]
}
