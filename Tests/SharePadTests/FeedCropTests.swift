import AVFoundation
@testable import SharePad
import SharePadWire
import XCTest

final class FeedCropTests: XCTestCase {
    // iPad mini portrait: 1488x2266 pixels, top bar 175 px tall, palette above 2009.
    private let crop = FeedCrop(
        width: 1488,
        height: 2266,
        canvas: CanvasRect(x: 0, y: 175, width: 1488, height: 1834)
    )

    func testVisibleSizeIsTheCanvasNotTheFrame() {
        XCTAssertEqual(crop?.visibleSize, CGSize(width: 1488, height: 1834))
    }

    func testTopBarSitsAboveTheVisibleAreaWhenYCountsDown() throws {
        let crop = try XCTUnwrap(crop)
        let bounds = CGRect(x: 0, y: 0, width: 744, height: 917)
        let frame = crop.videoFrame(in: bounds, yUp: false)
        XCTAssertEqual(frame, CGRect(x: 0, y: -87.5, width: 744, height: 1133))
    }

    func testTopBarSitsAboveTheVisibleAreaWhenYCountsUp() throws {
        let crop = try XCTUnwrap(crop)
        let bounds = CGRect(x: 0, y: 0, width: 744, height: 917)
        let frame = crop.videoFrame(in: bounds, yUp: true)
        XCTAssertEqual(frame, CGRect(x: 0, y: -128.5, width: 744, height: 1133))
        XCTAssertEqual(frame.maxY, 917 + 87.5, "the top 175 px row band lies above the bounds")
    }

    func testWiderWindowLetterboxesTheCanvas() throws {
        let crop = try XCTUnwrap(FeedCrop(
            width: 1000,
            height: 1000,
            canvas: CanvasRect(x: 0, y: 500, width: 1000, height: 500)
        ))
        let frame = crop.videoFrame(in: CGRect(x: 0, y: 0, width: 400, height: 400), yUp: false)
        XCTAssertEqual(frame, CGRect(x: 0, y: -100, width: 400, height: 400))
    }

    func testCanvasOutsideTheFrameIsClamped() {
        let clamped = FeedCrop(
            width: 100,
            height: 100,
            canvas: CanvasRect(x: 50, y: 50, width: 90, height: 90)
        )
        XCTAssertEqual(clamped?.canvas, CGRect(x: 50, y: 50, width: 50, height: 50))
    }

    func testEmptyFrameOrCanvasGivesNoCrop() {
        XCTAssertNil(FeedCrop(
            width: 0,
            height: 100,
            canvas: CanvasRect(x: 0, y: 0, width: 10, height: 10)
        ))
        XCTAssertNil(FeedCrop(
            width: 100,
            height: 100,
            canvas: CanvasRect(x: 0, y: 0, width: 0, height: 10)
        ))
    }

    func testLayerPlacesTheVideoFromTheCrop() throws {
        let video = AVSampleBufferDisplayLayer()
        let layer = CroppedVideoLayer(video: video)
        layer.isGeometryFlipped = true
        layer.frame = CGRect(x: 0, y: 0, width: 744, height: 917)
        layer.crop = try XCTUnwrap(crop)
        XCTAssertEqual(video.frame, CGRect(x: 0, y: -87.5, width: 744, height: 1133))
        XCTAssertEqual(video.videoGravity, .resize)
        layer.crop = nil
        XCTAssertEqual(video.frame, layer.bounds)
    }

    func testFlipParityCountsAncestors() {
        let outer = CALayer()
        let inner = CALayer()
        outer.addSublayer(inner)
        XCTAssertFalse(CroppedVideoLayer.isFlipped(inner))
        outer.isGeometryFlipped = true
        XCTAssertTrue(CroppedVideoLayer.isFlipped(inner))
        inner.isGeometryFlipped = true
        XCTAssertFalse(CroppedVideoLayer.isFlipped(inner))
    }
}
