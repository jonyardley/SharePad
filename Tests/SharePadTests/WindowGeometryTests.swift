@testable import SharePad
import XCTest

final class WindowGeometryTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)

    func testPlacedOriginKeepsOnscreenOriginUnchanged() throws {
        let origin = try XCTUnwrap(placedOrigin(
            savedOrigin: CGPoint(x: 100, y: 120),
            size: CGSize(width: 400, height: 600),
            onScreens: [screen]
        ))
        XCTAssertEqual(origin.x, 100, accuracy: 0.5)
        XCTAssertEqual(origin.y, 120, accuracy: 0.5)
    }

    func testPlacedOriginClampsPartlyOffscreenWindowBackIn() throws {
        let size = CGSize(width: 400, height: 600)
        let origin = try XCTUnwrap(placedOrigin(
            savedOrigin: CGPoint(x: 1300, y: 700),
            size: size,
            onScreens: [screen]
        ))
        XCTAssertEqual(origin.x, screen.maxX - size.width, accuracy: 0.5)
        XCTAssertEqual(origin.y, screen.maxY - size.height, accuracy: 0.5)
    }

    func testPlacedOriginReturnsNilWhenNoScreenOverlaps() {
        XCTAssertNil(placedOrigin(
            savedOrigin: CGPoint(x: 5000, y: 5000),
            size: CGSize(width: 400, height: 600),
            onScreens: [screen]
        ))
    }

    func testPlacedOriginClampsIntoTheMoreOverlappingScreen() throws {
        let secondScreen = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
        let size = CGSize(width: 400, height: 600)
        // Straddles both screens but overlaps the second more, so it must land there.
        let origin = try XCTUnwrap(placedOrigin(
            savedOrigin: CGPoint(x: 1340, y: 100),
            size: size,
            onScreens: [screen, secondScreen]
        ))
        XCTAssertGreaterThanOrEqual(origin.x, secondScreen.minX)
        XCTAssertLessThanOrEqual(origin.x + size.width, secondScreen.maxX + 0.5)
    }

    func testCenteredResizeKeepsCenterFixed() {
        let old = CGRect(x: 100, y: 100, width: 400, height: 600)
        let newSize = CGSize(width: 600, height: 400)
        let origin = centeredResizeOrigin(oldFrame: old, newSize: newSize, onScreens: [screen])
        XCTAssertEqual(origin.x + newSize.width / 2, old.midX, accuracy: 0.5)
        XCTAssertEqual(origin.y + newSize.height / 2, old.midY, accuracy: 0.5)
    }

    func testCenteredResizeClampsWhenReshapeSpillsOffscreen() {
        let old = CGRect(x: 1300, y: 100, width: 120, height: 120)
        let newSize = CGSize(width: 400, height: 400)
        let origin = centeredResizeOrigin(oldFrame: old, newSize: newSize, onScreens: [screen])
        XCTAssertGreaterThanOrEqual(origin.x, screen.minX)
        XCTAssertGreaterThanOrEqual(origin.y, screen.minY)
        XCTAssertLessThanOrEqual(origin.x + newSize.width, screen.maxX + 0.5)
        XCTAssertLessThanOrEqual(origin.y + newSize.height, screen.maxY + 0.5)
    }
}
