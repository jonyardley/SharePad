import CoreGraphics
@testable import SharePadPad
import XCTest

final class BoardTests: XCTestCase {
    private let view = CGSize(width: 1000, height: 800)

    func testHomeShowsTheOldCanvasAtFullSize() {
        let home = Board.position(of: Board.home, in: view)
        XCTAssertEqual(home, BoardPosition(centre: CGPoint(x: 500, y: 400), zoom: 1))
        XCTAssertEqual(Board.viewport(for: home, in: view), Board.home)
    }

    func testPositionRoundTripsThroughAViewport() {
        let position = BoardPosition(centre: CGPoint(x: -1200, y: 300), zoom: 0.5)
        let viewport = Board.viewport(for: position, in: view)
        XCTAssertEqual(Board.position(of: viewport, in: view), position)
    }

    func testZoomIsClampedToTheAllowedRange() {
        let position = BoardPosition(centre: .zero, zoom: 10)
        XCTAssertEqual(Board.viewport(for: position, in: view).zoom, Board.zoomRange.upperBound)
    }

    func testOffsetStaysOnTheBoard() {
        let position = BoardPosition(centre: CGPoint(x: -Board.extent * 2, y: 0), zoom: 1)
        XCTAssertEqual(Board.viewport(for: position, in: view).offset.x, 0)
    }

    func testFitOnAnEmptyDrawingGoesHome() {
        XCTAssertEqual(Board.fit(.null, in: view), Board.home)
    }

    func testFitZoomsOutToFrameALargeDrawingWithAMargin() {
        let drawing = CGRect(x: -1500, y: 0, width: 3000, height: 1000)
        let viewport = Board.fit(drawing, in: view)
        let expectedZoom = (view.width - Board.fitMargin * 2) / drawing.width
        XCTAssertEqual(viewport.zoom, expectedZoom, accuracy: 0.0001)
        let centre = Board.position(of: viewport, in: view).centre
        XCTAssertEqual(centre.x, 0, accuracy: 0.001)
        XCTAssertEqual(centre.y, 500, accuracy: 0.001)
    }

    func testFitStopsAtTheSmallestZoom() {
        let drawing = CGRect(x: 0, y: 0, width: 20000, height: 1000)
        XCTAssertEqual(Board.fit(drawing, in: view).zoom, Board.zoomRange.lowerBound)
    }

    func testFitNeverZoomsInPastFullSize() {
        let drawing = CGRect(x: 10, y: 10, width: 50, height: 50)
        XCTAssertEqual(Board.fit(drawing, in: view).zoom, 1)
    }
}

final class PaperGridTests: XCTestCase {
    private let size = CGSize(width: 100, height: 70)

    func testHomeMatchesTheOldFixedPaper() {
        let grid = PaperGrid(spacing: 32, minimumGap: 24, viewport: Board.home, size: size)
        XCTAssertEqual(grid.columns, [32, 64, 96])
        XCTAssertEqual(grid.rows, [32, 64])
    }

    func testLinesFollowAPan() {
        let viewport = Viewport(
            offset: CGPoint(x: Board.origin.x + 10, y: Board.origin.y - 5),
            zoom: 1
        )
        let grid = PaperGrid(spacing: 32, minimumGap: 24, viewport: viewport, size: size)
        XCTAssertEqual(grid.columns, [22, 54, 86])
        XCTAssertEqual(grid.rows, [5, 37, 69])
    }

    func testLinesScaleWithZoom() {
        let viewport = Viewport(
            offset: CGPoint(x: Board.origin.x * 2, y: Board.origin.y * 2),
            zoom: 2
        )
        let grid = PaperGrid(spacing: 32, minimumGap: 24, viewport: viewport, size: size)
        XCTAssertEqual(grid.columns, [64])
    }

    func testZoomedOutPaperThinsOut() {
        let viewport = Viewport(
            offset: CGPoint(x: Board.origin.x / 4, y: Board.origin.y / 4),
            zoom: 0.25
        )
        let grid = PaperGrid(spacing: 32, minimumGap: 24, viewport: viewport, size: size)
        XCTAssertEqual(grid.columns, [32, 64, 96])
    }

    func testZeroZoomDrawsNoPaper() {
        let viewport = Viewport(offset: .zero, zoom: 0)
        let grid = PaperGrid(spacing: 32, minimumGap: 24, viewport: viewport, size: size)
        XCTAssertTrue(grid.columns.isEmpty)
    }
}
