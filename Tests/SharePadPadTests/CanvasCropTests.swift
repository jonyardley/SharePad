import CoreGraphics
@testable import SharePadPad
import SharePadWire
import XCTest

final class CanvasCropTests: XCTestCase {
    private let window = CGSize(width: 1000, height: 800)
    private let canvas = CGRect(x: 0, y: 60, width: 1000, height: 740)

    func testNoObstructionSharesTheWholeCanvas() {
        let layout = CanvasLayout(canvas: canvas, window: window)
        XCTAssertEqual(CanvasCrop.shareableRect(of: layout), canvas)
    }

    func testDockedToolPickerIsCroppedOffTheBottom() {
        let picker = CGRect(x: 0, y: 700, width: 1000, height: 100)
        let layout = CanvasLayout(canvas: canvas, window: window, obstructions: [picker])
        XCTAssertEqual(
            CanvasCrop.shareableRect(of: layout),
            CGRect(x: 0, y: 60, width: 1000, height: 640)
        )
    }

    func testFloatingPickerKeepsTheLargestClearStrip() {
        let picker = CGRect(x: 850, y: 300, width: 100, height: 300)
        let layout = CanvasLayout(canvas: canvas, window: window, obstructions: [picker])
        XCTAssertEqual(
            CanvasCrop.shareableRect(of: layout),
            CGRect(x: 0, y: 60, width: 850, height: 740)
        )
    }

    func testObstructionOutsideTheCanvasIsIgnored() {
        let topBar = CGRect(x: 0, y: 0, width: 1000, height: 60)
        let layout = CanvasLayout(canvas: canvas, window: window, obstructions: [topBar])
        XCTAssertEqual(CanvasCrop.shareableRect(of: layout), canvas)
    }

    func testCropScalesPointsToBufferPixels() {
        let layout = CanvasLayout(canvas: canvas, window: window)
        let rect = CanvasCrop.pixelRect(
            for: layout,
            bufferWidth: 2000,
            bufferHeight: 1600,
            orientation: .up
        )
        XCTAssertEqual(rect, CanvasRect(x: 0, y: 120, width: 2000, height: 1480))
    }

    func testCropNeverLeavesTheBuffer() {
        let layout = CanvasLayout(
            canvas: CGRect(x: -10, y: 60, width: 1020, height: 760),
            window: window
        )
        let rect = CanvasCrop.pixelRect(
            for: layout,
            bufferWidth: 1000,
            bufferHeight: 800,
            orientation: .up
        )
        XCTAssertEqual(rect, CanvasRect(x: 0, y: 60, width: 1000, height: 740))
    }

    func testRotatedBufferMapsIntoStoredPixels() {
        let layout = CanvasLayout(canvas: canvas, window: window)
        let right = CanvasCrop.pixelRect(
            for: layout,
            bufferWidth: 800,
            bufferHeight: 1000,
            orientation: .right
        )
        XCTAssertEqual(right, CanvasRect(x: 60, y: 0, width: 740, height: 1000))
        let left = CanvasCrop.pixelRect(
            for: layout,
            bufferWidth: 800,
            bufferHeight: 1000,
            orientation: .left
        )
        XCTAssertEqual(left, CanvasRect(x: 0, y: 0, width: 740, height: 1000))
    }

    func testUpsideDownBufferFlipsBothAxes() {
        let layout = CanvasLayout(canvas: canvas, window: window)
        let rect = CanvasCrop.pixelRect(
            for: layout,
            bufferWidth: 1000,
            bufferHeight: 800,
            orientation: .down
        )
        XCTAssertEqual(rect, CanvasRect(x: 0, y: 0, width: 1000, height: 740))
    }

    func testEmptyLayoutGivesNoCrop() {
        let layout = CanvasLayout(canvas: .zero, window: window)
        XCTAssertNil(CanvasCrop.pixelRect(
            for: layout,
            bufferWidth: 1000,
            bufferHeight: 800,
            orientation: .up
        ))
    }

    func testFractionalCropRoundsInward() {
        let layout = CanvasLayout(
            canvas: CGRect(x: 0, y: 60.25, width: 1000, height: 739.5),
            window: window
        )
        let rect = CanvasCrop.pixelRect(
            for: layout,
            bufferWidth: 1000,
            bufferHeight: 800,
            orientation: .up
        )
        XCTAssertEqual(rect, CanvasRect(x: 0, y: 61, width: 1000, height: 738))
    }
}
