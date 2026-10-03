@testable import SharePadPad
import SharePadWire
import XCTest

final class PairingStateTests: XCTestCase {
    private func record(_ name: String, lastConnected: TimeInterval) -> PairingRecord {
        PairingRecord(
            peerID: UUID(),
            peerName: name,
            pairingID: UUID(),
            secret: .generate(),
            pairedAt: 1,
            lastConnectedAt: lastConnected
        )
    }

    func testNothingPairedIsUnpaired() {
        XCTAssertEqual(PairingState(records: [], broken: []), .unpaired)
    }

    func testAHealthyPairingIsPaired() {
        XCTAssertEqual(PairingState(records: [record("Studio", lastConnected: 5)], broken: []),
                       .paired)
    }

    func testTheMostRecentlyUsedBrokenMacIsNamed() {
        let home = record("Home", lastConnected: 10)
        let work = record("Work", lastConnected: 20)
        XCTAssertEqual(
            PairingState(records: [home, work], broken: [home.peerID, work.peerID]),
            .broken("Work")
        )
        XCTAssertEqual(
            PairingState(records: [home, work], broken: [home.peerID]),
            .broken("Home")
        )
    }
}

final class TypedCodeTests: XCTestCase {
    func testTypingIsGroupedInFoursAndUppercased() {
        XCTAssertEqual(TypedCode.format("k7qm4x"), "K7QM-4X")
        XCTAssertEqual(TypedCode.format("K7QM 4XRT·9WPA"), "K7QM-4XRT-9WPA")
        XCTAssertEqual(TypedCode.format(""), "")
    }

    func testCharactersOutsideTheCodeAreDroppedAndLengthIsCapped() {
        XCTAssertEqual(TypedCode.format("ab!u?cd"), "ABCD")
        XCTAssertEqual(TypedCode.format(String(repeating: "A", count: 30)).count, 24 + 5)
    }

    func testLookalikesAreKeptAndReadAsDigits() {
        let code = PairingCode.generate()
        let typed = code.typed.replacingOccurrences(of: "0", with: "O")
            .replacingOccurrences(of: "1", with: "l")
        XCTAssertEqual(TypedCode.code(from: TypedCode.format(typed)), code)
    }

    func testAShortCodeIsNotComplete() {
        XCTAssertNil(TypedCode.code(from: "K7QM-4XRT"))
    }

    func testAScannedLinkOrRawCodeIsAccepted() throws {
        let code = PairingCode.generate()
        let link = try XCTUnwrap(code.invitationURL).absoluteString
        XCTAssertEqual(TypedCode.code(scanned: link), code)
        XCTAssertEqual(TypedCode.code(scanned: code.typed), code)
        XCTAssertNil(TypedCode.code(scanned: "https://example.com/pair#v1.ABCD"))
        XCTAssertNil(TypedCode.code(scanned: "hello"))
    }
}

final class PairingScreenContentTests: XCTestCase {
    private let mac = Hello(deviceID: UUID(), deviceName: "Jon’s MacBook Pro")

    private func content(
        _ phase: PadPairing.Phase,
        saveFailed: Bool = false,
        hasPairings: Bool = true
    ) -> PairingScreenContent {
        PairingScreenContent(phase: phase, saveFailed: saveFailed, hasPairings: hasPairings)
    }

    func testFirstRunNamesTheMacAppAsPlainText() {
        XCTAssertTrue(content(.idle, hasPairings: false).showsMacAppNote)
        XCTAssertFalse(content(.idle).showsMacAppNote)
        XCTAssertEqual(
            PairingScreenContent.macAppNote,
            "You also need SharePad on your Mac: sharepad.co"
        )
    }

    func testEachPhaseSaysWhatIsHappening() {
        XCTAssertNil(content(.idle).status)
        XCTAssertEqual(content(.searching).status, "Looking for your Mac…")
        XCTAssertEqual(content(.trying("Studio")).status, "Trying Studio…")
        XCTAssertEqual(content(.awaitingGrant("Studio", mac: nil)).status, "Trying Studio…")
        XCTAssertEqual(
            content(.awaitingGrant("Studio", mac: mac)).status,
            "Pairing with Jon’s MacBook Pro…"
        )
        XCTAssertTrue(content(.searching).isWorking)
        XCTAssertFalse(content(.idle).isWorking)
    }

    func testPairedConfirmsWithTheMacName() {
        let record = PairingRecord(
            peerID: mac.deviceID,
            peerName: mac.deviceName,
            pairingID: UUID(),
            secret: .generate(),
            pairedAt: 1
        )
        let paired = content(.paired(record))
        XCTAssertEqual(paired.status, "Paired with Jon’s MacBook Pro")
        XCTAssertTrue(paired.isPaired)
        XCTAssertFalse(paired.isWorking)
    }

    func testFailuresSayWhatToDo() {
        XCTAssertEqual(
            content(.failed(.noMacAccepted)).status,
            "No Mac accepted that code. Check it matches the one on your Mac, "
                + "and that both are on the same Wi-Fi."
        )
        XCTAssertEqual(
            content(.idle, saveFailed: true).status,
            "This iPad couldn’t save the pairing. Try again."
        )
    }

    func testIPadCopyNeverMentionsPriceTrialOrLicence() {
        let texts = [PairingScreenContent.macAppNote, PairingScreenContent.recordPromptNote]
            + PairingScreenContent.steps + [
                content(.failed(.noMacAccepted)).status,
                content(.idle, saveFailed: true).status,
            ].compactMap(\.self)
        for text in texts {
            for word in ["buy", "free", "trial", "licence", "license", "price"] {
                XCTAssertFalse(text.lowercased().contains(word), text)
            }
        }
    }
}
