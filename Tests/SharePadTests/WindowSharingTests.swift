import AppKit
@testable import SharePad
import XCTest

@MainActor
final class WindowSharingTests: XCTestCase {
    func testFeedWindowIsNotExcluded() {
        XCTAssertFalse(WindowSharing.excludesFromSharing(WindowSharing.shareWindowID))
    }

    func testAuxiliaryWindowIsExcluded() {
        XCTAssertTrue(WindowSharing
            .excludesFromSharing(NSUserInterfaceItemIdentifier("SharePad.about")))
    }

    func testUnidentifiedWindowIsExcluded() {
        XCTAssertTrue(WindowSharing.excludesFromSharing(nil))
    }
}
