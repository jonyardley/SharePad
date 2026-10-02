import Foundation
@testable import SharePadWire
import XCTest

final class PairingRulesTests: XCTestCase {
    private let pad = Hello(deviceID: UUID(), deviceName: "Jon’s iPad")
    private let offer = PairingOffer(pairingID: UUID(), issuedAt: 100)

    func testOpeningStartsAdvertisingAndARedeemStoresTheIPad() {
        var window = PairingWindow()
        XCTAssertEqual(window.reduce(.open(offer)), [.startAdvertising])
        let device = PairedDevice(deviceID: pad.deviceID, name: pad.deviceName, pairedAt: 160)
        XCTAssertEqual(
            window.reduce(.handshakeSucceeded(pairingID: offer.pairingID, peer: pad, at: 160)),
            [.store(device), .stopAdvertising]
        )
        XCTAssertEqual(window.phase, .paired(device))
    }

    func testCodeExpiresAfterFiveMinutes() {
        var window = PairingWindow()
        _ = window.reduce(.open(offer))
        XCTAssertEqual(window.reduce(.tick(at: 399)), [])
        XCTAssertEqual(window.reduce(.tick(at: 400)), [.stopAdvertising])
        XCTAssertEqual(window.phase, .expired)
        XCTAssertEqual(
            window.reduce(.handshakeSucceeded(pairingID: offer.pairingID, peer: pad, at: 401)),
            [.reject(.unknownCode)]
        )
    }

    func testRedeemAfterExpiryWithoutATickIsStillRejected() {
        var window = PairingWindow()
        _ = window.reduce(.open(offer))
        XCTAssertEqual(
            window.reduce(.handshakeSucceeded(pairingID: offer.pairingID, peer: pad, at: 500)),
            [.reject(.expired), .stopAdvertising]
        )
    }

    func testCodeIsSingleUse() {
        var window = PairingWindow()
        _ = window.reduce(.open(offer))
        _ = window.reduce(.handshakeSucceeded(pairingID: offer.pairingID, peer: pad, at: 110))
        let other = Hello(deviceID: UUID(), deviceName: "Other")
        XCTAssertEqual(
            window.reduce(.handshakeSucceeded(pairingID: offer.pairingID, peer: other, at: 111)),
            [.reject(.alreadyUsed)]
        )
    }

    func testWrongCodeIsRejected() {
        var window = PairingWindow()
        _ = window.reduce(.open(offer))
        XCTAssertEqual(
            window.reduce(.handshakeSucceeded(pairingID: UUID(), peer: pad, at: 110)),
            [.reject(.unknownCode)]
        )
    }

    func testClosingWhileOfferingStopsAdvertising() {
        var window = PairingWindow()
        _ = window.reduce(.open(offer))
        XCTAssertEqual(window.reduce(.close), [.stopAdvertising])
        XCTAssertEqual(window.reduce(.close), [])
    }

    func testRepairingReplacesTheOldEntry() {
        var devices = PairedDevices()
        devices.store(PairedDevice(deviceID: pad.deviceID, name: "Old name", pairedAt: 1))
        devices.store(PairedDevice(deviceID: pad.deviceID, name: pad.deviceName, pairedAt: 2))
        XCTAssertEqual(devices.devices.count, 1)
        XCTAssertEqual(devices.devices.first?.name, pad.deviceName)
        devices.forget(pad.deviceID)
        XCTAssertTrue(devices.devices.isEmpty)
    }

    func testThreeFailedHandshakesInARowMarkAPairingBroken() {
        var health = PairingHealth()
        let id = pad.deviceID
        XCTAssertEqual(health.reduce(.handshakeFailed(id)), [])
        XCTAssertEqual(health.reduce(.handshakeFailed(id)), [])
        XCTAssertEqual(health.reduce(.handshakeFailed(id)), [.markBroken(id)])
        XCTAssertTrue(health.isBroken(id))
        XCTAssertEqual(health.reduce(.handshakeFailed(id)), [])
        XCTAssertEqual(health.reduce(.handshakeSucceeded(id)), [.markHealthy(id)])
        XCTAssertFalse(health.isBroken(id))
    }

    func testASuccessResetsTheCount() {
        var health = PairingHealth()
        let id = pad.deviceID
        _ = health.reduce(.handshakeFailed(id))
        _ = health.reduce(.handshakeFailed(id))
        XCTAssertEqual(health.reduce(.handshakeSucceeded(id)), [])
        XCTAssertEqual(health.reduce(.handshakeFailed(id)), [])
        XCTAssertFalse(health.isBroken(id))
    }
}
