import CoreMedia
import CoreVideo
@testable import SharePadPad
import SharePadWire
import XCTest

final class CaptureContextTests: XCTestCase {
    func testACanvasOnlyFrameGoesOutWholeWithNoLayout() throws {
        let decision = try CaptureContext().decide(for: frame(isCanvasOnly: true), at: 0)
        XCTAssertEqual(decision, .init(allowed: true, crop: .whole(width: 40, height: 30)))
    }

    func testACanvasOnlyFrameIgnoresOverlays() throws {
        let context = CaptureContext()
        context.overlay(.settings, shown: true, at: 0)
        XCTAssertTrue(try context.decide(for: frame(isCanvasOnly: true), at: 1).allowed)
    }

    func testAScreenFrameWithNoLayoutIsHeld() throws {
        let decision = try CaptureContext().decide(for: frame(isCanvasOnly: false), at: 0)
        XCTAssertEqual(decision, .init(allowed: false, crop: nil))
    }

    private func frame(isCanvasOnly: Bool) throws -> CapturedFrame {
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(nil, 40, 30, kCVPixelFormatType_32BGRA, nil, &buffer)
        return try CapturedFrame(
            pixelBuffer: XCTUnwrap(buffer),
            presentationTime: .zero,
            orientation: .up,
            isCanvasOnly: isCanvasOnly
        )
    }
}
