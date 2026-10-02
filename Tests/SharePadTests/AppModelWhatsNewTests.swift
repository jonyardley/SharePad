@testable import SharePad
import XCTest

@MainActor
final class AppModelWhatsNewTests: AppModelTestCase {
    private var requests = 0

    private func upgradedPreferences(lastSeen: String?) throws -> Preferences {
        let prefs = try ephemeralPreferences()
        prefs.firstLaunchDate = Date(timeIntervalSince1970: 0)
        prefs.lastSeenVersion = lastSeen
        return prefs
    }

    private func model(
        _ prefs: Preferences,
        capture: FakeCaptureController = FakeCaptureController(),
        window: FakeShareWindow = FakeShareWindow(),
        version: String = "1.3"
    ) -> AppModel {
        let model = makeModel(
            capture: capture,
            window: window,
            preferences: prefs,
            appVersion: version,
            featureReleases: ["1.3"]
        )
        model.onWhatsNewRequested = { [weak self] in self?.requests += 1 }
        return model
    }

    func testShowsAfterUpdatingToAFeatureRelease() async throws {
        let prefs = try upgradedPreferences(lastSeen: "1.2")
        await model(prefs).checkWhatsNew()
        XCTAssertEqual(requests, 1)
        XCTAssertEqual(prefs.lastSeenVersion, "1.2", "only dismissing marks it seen")
    }

    func testDismissingMarksTheVersionSeen() async throws {
        let prefs = try upgradedPreferences(lastSeen: "1.2")
        let model = model(prefs)
        await model.checkWhatsNew()
        model.markWhatsNewSeen()
        XCTAssertEqual(prefs.lastSeenVersion, "1.3")
        await self.model(prefs).checkWhatsNew()
        XCTAssertEqual(requests, 1, "shown once")
    }

    func testFreshInstallRecordsSilently() async throws {
        let prefs = try ephemeralPreferences()
        await model(prefs).checkWhatsNew()
        XCTAssertEqual(requests, 0)
        XCTAssertEqual(prefs.lastSeenVersion, "1.3")
    }

    func testInstallFromBeforeTheRecordShows() async throws {
        let prefs = try upgradedPreferences(lastSeen: nil)
        await model(prefs).checkWhatsNew()
        XCTAssertEqual(requests, 1)
    }

    func testBugFixReleaseRecordsSilently() async throws {
        let prefs = try upgradedPreferences(lastSeen: "1.3")
        await model(prefs, version: "1.3.1").checkWhatsNew()
        XCTAssertEqual(requests, 0)
        XCTAssertEqual(prefs.lastSeenVersion, "1.3.1")
    }

    func testDowngradeKeepsTheNewerRecord() async throws {
        let prefs = try upgradedPreferences(lastSeen: "1.4")
        await model(prefs).checkWhatsNew()
        XCTAssertEqual(requests, 0)
        XCTAssertEqual(prefs.lastSeenVersion, "1.4")
    }

    func testWaitsWhileTheShareWindowIsUpThenShowsWhenItCloses() async throws {
        let prefs = try upgradedPreferences(lastSeen: "1.2")
        let window = FakeShareWindow()
        let model = model(prefs, window: window)
        await model.reconcile(devices: [device("a")])
        XCTAssertTrue(model.isWindowVisible)

        await model.checkWhatsNew()
        XCTAssertEqual(requests, 0, "never mid-call")
        XCTAssertTrue(model.isWhatsNewDue)

        model.toggleWindow()
        XCTAssertEqual(requests, 1)
        XCTAssertFalse(model.isWhatsNewDue)
    }

    func testWaitsUntilTheIPadIsUnplugged() async throws {
        let prefs = try upgradedPreferences(lastSeen: "1.2")
        let model = model(prefs)
        await model.reconcile(devices: [device("a")])
        await model.checkWhatsNew()
        XCTAssertEqual(requests, 0)

        await model.reconcile(devices: [])
        XCTAssertEqual(requests, 1)
    }

    func testWaitsWhileTheWindowIsShowingEvenIfTheModelThinksItIsHidden() async throws {
        let prefs = try upgradedPreferences(lastSeen: "1.2")
        let window = FakeShareWindow()
        window.isShowing = true
        await model(prefs, window: window).checkWhatsNew()
        XCTAssertEqual(requests, 0)
    }

    func testClosingTheShareWindowWithNothingDueShowsNothing() async throws {
        let prefs = try upgradedPreferences(lastSeen: "1.3")
        let model = model(prefs)
        await model.checkWhatsNew()
        await model.reconcile(devices: [device("a")])
        model.toggleWindow()
        XCTAssertEqual(requests, 0)
    }

    func testShowsOnlyOnceAcrossRepeatedShareWindowCloses() async throws {
        let prefs = try upgradedPreferences(lastSeen: "1.2")
        let model = model(prefs)
        await model.reconcile(devices: [device("a")])
        await model.checkWhatsNew()
        model.toggleWindow()
        model.toggleWindow()
        model.toggleWindow()
        XCTAssertEqual(requests, 1)
    }
}
