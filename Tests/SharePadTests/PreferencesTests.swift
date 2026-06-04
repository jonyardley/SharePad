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

    private func makeEphemeralDefaults() throws -> UserDefaults {
        let name = "sharepad.tests.\(UUID().uuidString)"
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: name) }
        return try XCTUnwrap(UserDefaults(suiteName: name))
    }
}
