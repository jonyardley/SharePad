import PencilKit
@testable import SharePadPad
import XCTest

final class PadPreferencesTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "SharePadPadTests.preferences"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func testDefaultsToPlainLightPaper() {
        XCTAssertEqual(PadPreferences(defaults: defaults).paper, Paper(style: .plain, tone: .light))
    }

    func testPaperRoundTrips() {
        PadPreferences(defaults: defaults).paper = Paper(style: .dots, tone: .dark)
        XCTAssertEqual(PadPreferences(defaults: defaults).paper, Paper(style: .dots, tone: .dark))
    }

    func testUnknownStoredValuesFallBack() {
        defaults.set("lined", forKey: "paperStyle")
        defaults.set("sepia", forKey: "paperTone")
        XCTAssertEqual(PadPreferences(defaults: defaults).paper, Paper())
    }

    func testBoardPositionRoundTrips() {
        let preferences = PadPreferences(defaults: defaults)
        XCTAssertNil(preferences.boardPosition)
        let position = BoardPosition(centre: CGPoint(x: -300, y: 1200), zoom: 0.5)
        preferences.boardPosition = position
        XCTAssertEqual(PadPreferences(defaults: defaults).boardPosition, position)
    }

    func testLastMacRoundTrips() {
        let preferences = PadPreferences(defaults: defaults)
        XCTAssertNil(preferences.lastMac)
        preferences.lastMac = "Studio"
        XCTAssertEqual(PadPreferences(defaults: defaults).lastMac, "Studio")
    }
}

final class DrawingStoreTests: XCTestCase {
    private var directory: URL!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    func testMissingFileLoadsBlank() {
        XCTAssertTrue(DrawingStore(directory: directory).load().strokes.isEmpty)
    }

    func testDrawingRoundTrips() throws {
        let stroke = PKStroke(
            ink: PKInk(.pen, color: .black),
            path: PKStrokePath(
                controlPoints: [
                    PKStrokePoint(
                        location: .zero, timeOffset: 0, size: CGSize(width: 4, height: 4),
                        opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2
                    ),
                    PKStrokePoint(
                        location: CGPoint(x: 50, y: 50), timeOffset: 0.1,
                        size: CGSize(width: 4, height: 4),
                        opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2
                    ),
                ],
                creationDate: Date()
            )
        )
        let store = DrawingStore(directory: directory)
        try store.save(PKDrawing(strokes: [stroke]))
        XCTAssertEqual(DrawingStore(directory: directory).load().strokes.count, 1)
    }

    func testCorruptFileLoadsBlank() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not a drawing".utf8)
            .write(to: directory.appendingPathComponent("drawing.pkdrawing"))
        XCTAssertTrue(DrawingStore(directory: directory).load().strokes.isEmpty)
    }
}
