@testable import SharePad
import XCTest

final class LicenseStoreTests: XCTestCase {
    private func ephemeralPreferences() throws -> Preferences {
        let name = "sharepad.tests.\(UUID().uuidString)"
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: name) }
        return try Preferences(defaults: XCTUnwrap(UserDefaults(suiteName: name)))
    }

    func testFirstLaunchWrittenOnceThenStable() throws {
        let store = try LicenseStore(preferences: ephemeralPreferences())
        let first = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(store.firstLaunch(now: first), first)
        // A later call returns the original, not the new `now`.
        XCTAssertEqual(store.firstLaunch(now: first.addingTimeInterval(99999)), first)
    }

    func testLicenseRoundTrips() throws {
        let prefs = try ephemeralPreferences()
        let store = LicenseStore(preferences: prefs)
        XCTAssertNil(store.name)
        XCTAssertNil(store.key)
        store.save(name: "Jon", key: "abc")
        let reloaded = LicenseStore(preferences: prefs)
        XCTAssertEqual(reloaded.name, "Jon")
        XCTAssertEqual(reloaded.key, "abc")
    }
}
