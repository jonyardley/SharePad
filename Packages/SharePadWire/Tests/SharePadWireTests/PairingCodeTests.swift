import CryptoKit
import Foundation
@testable import SharePadWire
import XCTest

private struct CountingGenerator: RandomNumberGenerator {
    var state: UInt64 = 0

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        return state
    }
}

final class PairingCodeTests: XCTestCase {
    func testTypedCodeIsSixGroupsOfFourFromTheUnambiguousAlphabet() {
        let code = PairingCode.generate()
        let groups = code.typed.split(separator: "-")
        XCTAssertEqual(groups.count, 6)
        XCTAssertTrue(groups.allSatisfy { $0.count == 4 })
        let allowed = Set(PairingCode.alphabet)
        XCTAssertTrue(code.typed.replacingOccurrences(of: "-", with: "")
            .allSatisfy(allowed.contains))
        for ambiguous in "ILOU" {
            XCTAssertFalse(code.typed.contains(ambiguous))
        }
    }

    func testCarriesOneHundredAndTwentyBits() {
        XCTAssertEqual(PairingCode.byteCount * 8, 120)
        XCTAssertEqual(PairingCode.generate().bytes.count, 15)
    }

    func testTypedCodeRoundTrips() {
        let code = PairingCode.generate()
        XCTAssertEqual(PairingCode(typed: code.typed), code)
    }

    func testTypedCodeToleratesCaseSpacingAndLookalikes() throws {
        let code = try XCTUnwrap(PairingCode(typed: "0123-4567-89AB-CDEF-GHJK-MNPQ"))
        XCTAssertEqual(PairingCode(typed: "o123 4567 89ab cdef ghjk mnpq"), code)
        XCTAssertEqual(PairingCode(typed: "0I23-4567-89AB-CDEF-GHJK-MNPQ"), code)
        XCTAssertEqual(PairingCode(typed: "0l23·4567·89AB·CDEF·GHJK·MNPQ"), code)
    }

    func testTypedCodeRejectsWrongLengthAndUnknownLetters() {
        XCTAssertNil(PairingCode(typed: "0123-4567-89AB-CDEF-GHJK-MNP"))
        XCTAssertNil(PairingCode(typed: "0123-4567-89AB-CDEF-GHJK-MNPQR"))
        XCTAssertNil(PairingCode(typed: "U123-4567-89AB-CDEF-GHJK-MNPQ"))
        XCTAssertNil(PairingCode(typed: "!123-4567-89AB-CDEF-GHJK-MNPQ"))
        XCTAssertNil(PairingCode(typed: ""))
    }

    func testBytesRoundTripThroughTheAlphabet() throws {
        let bytes = Data((0 ..< 15).map { UInt8($0 * 17) })
        let code = try XCTUnwrap(PairingCode(bytes: bytes))
        XCTAssertEqual(PairingCode(typed: code.typed)?.bytes, bytes)
        XCTAssertNil(PairingCode(bytes: Data(count: 14)))
    }

    func testGenerationUsesTheGivenGenerator() {
        var first = CountingGenerator()
        var second = CountingGenerator()
        XCTAssertEqual(PairingCode.generate(using: &first), PairingCode.generate(using: &second))
        XCTAssertNotEqual(PairingCode.generate(), PairingCode.generate())
    }

    func testInvitationLinkRoundTrips() throws {
        let code = PairingCode.generate()
        let url = try XCTUnwrap(code.invitationURL)
        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, "sharepad.co")
        XCTAssertEqual(url.path, "/pair")
        XCTAssertNil(url.query)
        XCTAssertEqual(PairingCode(invitation: url), code)
    }

    func testInvitationLinkKeepsTheCodeOutOfThePartSentToTheServer() throws {
        let code = PairingCode.generate()
        let compact = code.typed.replacingOccurrences(of: "-", with: "")
        let url = try XCTUnwrap(code.invitationURL)
        XCTAssertFalse(url.path.contains(compact))
        XCTAssertEqual(url.fragment, "v1.\(compact)")
    }

    func testInvitationLinkRejectsOtherSitesAndShapes() throws {
        let compact = PairingCode.generate().typed.replacingOccurrences(of: "-", with: "")
        let rejected = [
            "http://sharepad.co/pair#v1.\(compact)",
            "https://evil.example/pair#v1.\(compact)",
            "https://sharepad.co.evil.example/pair#v1.\(compact)",
            "https://sharepad.co/other#v1.\(compact)",
            "https://sharepad.co/pair#v2.\(compact)",
            "https://sharepad.co/pair?v1.\(compact)",
            "https://sharepad.co/pair#v1.\(compact)X",
            "https://sharepad.co/pair",
        ]
        for text in rejected {
            let url = try XCTUnwrap(URL(string: text))
            XCTAssertNil(PairingCode(invitation: url), text)
        }
        let upper = try XCTUnwrap(URL(string: "https://SharePad.co/pair#v1.\(compact)"))
        XCTAssertNotNil(PairingCode(invitation: upper))
    }

    func testDescriptionsNeverPrintTheSecret() {
        let code = PairingCode.generate()
        let compact = code.typed.replacingOccurrences(of: "-", with: "")
        for text in [String(describing: code), String(reflecting: code), "\(code)"] {
            XCTAssertFalse(text.contains(compact))
            XCTAssertFalse(text.contains(code.typed))
        }
        let secret = LinkSecret.generate()
        let hex = secret.bytes.map { String(format: "%02x", $0) }.joined()
        for text in [String(describing: secret), String(reflecting: secret)] {
            XCTAssertFalse(text.contains(hex))
        }
    }

    func testLinkSecretIsThirtyTwoBytesAndValidated() {
        XCTAssertEqual(LinkSecret.generate().bytes.count, 32)
        XCTAssertNotEqual(LinkSecret.generate(), LinkSecret.generate())
        XCTAssertNil(LinkSecret(bytes: Data(count: 31)))
        XCTAssertNotNil(LinkSecret(bytes: Data(count: 32)))
    }

    func testKeysAreSeparatedByPurposeAndSource() {
        let code = PairingCode.generate()
        let secret = LinkSecret.generate()
        let keys = [
            code.keys.tlsKey, code.keys.proofKey, secret.keys.tlsKey, secret.keys.proofKey,
        ].map { $0.withUnsafeBytes { Data($0) } }
        XCTAssertEqual(Set(keys).count, 4)
        XCTAssertTrue(keys.allSatisfy { $0.count == 32 })
        XCTAssertEqual(code.keys.tlsKey, code.keys.tlsKey)
    }
}
