@testable import SharePad
import XCTest

final class PreferencesTests: XCTestCase {
    func testDefaults() throws {
        let prefs = try Preferences(defaults: makeEphemeralDefaults())
        XCTAssertTrue(prefs.autoShowOnConnect)
        XCTAssertFalse(prefs.keepOnTop)
    }

    func testPersistsValues() throws {
        let defaults = try makeEphemeralDefaults()
        let prefs = Preferences(defaults: defaults)
        prefs.autoShowOnConnect = false
        prefs.keepOnTop = true

        let reloaded = Preferences(defaults: defaults)
        XCTAssertFalse(reloaded.autoShowOnConnect)
        XCTAssertTrue(reloaded.keepOnTop)
    }

    func testLastDeviceIDDefaultsToNil() throws {
        let prefs = try Preferences(defaults: makeEphemeralDefaults())
        XCTAssertNil(prefs.lastDeviceID)
    }

    func testLastDeviceIDRoundTrips() throws {
        let defaults = try makeEphemeralDefaults()
        let prefs = Preferences(defaults: defaults)
        prefs.lastDeviceID = "abc-123"

        XCTAssertEqual(Preferences(defaults: defaults).lastDeviceID, "abc-123")
    }

    func testWindowFrameDefaultsAreNil() throws {
        let prefs = try Preferences(defaults: makeEphemeralDefaults())
        XCTAssertNil(prefs.windowOrigin)
        XCTAssertNil(prefs.windowLongSide)
    }

    func testPersistsWindowFrame() throws {
        let defaults = try makeEphemeralDefaults()
        let prefs = Preferences(defaults: defaults)
        prefs.windowOrigin = CGPoint(x: 120, y: 340)
        prefs.windowLongSide = 720

        let reloaded = Preferences(defaults: defaults)
        let origin = try XCTUnwrap(reloaded.windowOrigin)
        XCTAssertEqual(origin.x, 120, accuracy: 0.5)
        XCTAssertEqual(origin.y, 340, accuracy: 0.5)
        XCTAssertEqual(try XCTUnwrap(reloaded.windowLongSide), 720, accuracy: 0.5)
    }

    func testClearingWindowOriginRemovesIt() throws {
        let defaults = try makeEphemeralDefaults()
        let prefs = Preferences(defaults: defaults)
        prefs.windowOrigin = CGPoint(x: 10, y: 20)
        prefs.windowOrigin = nil
        XCTAssertNil(Preferences(defaults: defaults).windowOrigin)
    }

    private func makeEphemeralDefaults() throws -> UserDefaults {
        let name = "sharepad.tests.\(UUID().uuidString)"
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: name) }
        return try XCTUnwrap(UserDefaults(suiteName: name))
    }
}
