import PencilKit
@testable import SharePadPad
import UIKit
import XCTest

@MainActor
final class CanvasUndoTests: XCTestCase {
    private var window: UIWindow?

    override func tearDown() {
        window?.isHidden = true
        window = nil
        super.tearDown()
    }

    func testUndoBringsBackAClearedDrawing() throws {
        let canvas = makeCanvas(drawing: PKDrawing(strokes: [Self.stroke]))
        let undoManager = try XCTUnwrap(canvas.hostView.undoManager)
        canvas.clear()
        XCTAssertFalse(canvas.hasStrokes)

        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        undoManager.undo()
        XCTAssertTrue(canvas.hasStrokes)

        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        undoManager.redo()
        XCTAssertFalse(canvas.hasStrokes)
    }

    func testClearReturnsToHomeView() {
        let canvas = makeCanvas(drawing: PKDrawing(strokes: [Self.longStroke]))
        canvas.fitDrawing()
        XCTAssertNotEqual(canvas.viewport.zoom, Board.home.zoom)

        canvas.clear()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        XCTAssertEqual(canvas.viewport.zoom, Board.home.zoom)
    }

    private func makeCanvas(drawing: PKDrawing) -> CanvasController {
        let canvas = CanvasController(drawing: drawing, position: nil)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 744, height: 1133))
        window.rootViewController = UIViewController()
        canvas.hostView.frame = window.bounds
        window.rootViewController?.view.addSubview(canvas.hostView)
        window.makeKeyAndVisible()
        self.window = window
        return canvas
    }

    private static let stroke = PKStroke(
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

    private static let longStroke = PKStroke(
        ink: PKInk(.pen, color: .black),
        path: PKStrokePath(
            controlPoints: [CGPoint.zero, CGPoint(x: 2400, y: 3000)].enumerated()
                .map { index, location in
                    PKStrokePoint(
                        location: location, timeOffset: TimeInterval(index) * 0.1,
                        size: CGSize(width: 4, height: 4),
                        opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2
                    )
                },
            creationDate: Date()
        )
    )
}
