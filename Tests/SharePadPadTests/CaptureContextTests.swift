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

    func testASecondLayoutHoldsFramesUntilTheRecropInterval() throws {
        let context = CaptureContext()
        context.setLayout(layout(), at: 0)
        let changedAt: TimeInterval = 10
        context.setLayout(
            layout(canvas: CGRect(x: 0, y: 0, width: 400, height: 150)),
            at: changedAt
        )
        let crop = CanvasRect(x: 0, y: 0, width: 40, height: 15)

        XCTAssertEqual(
            try context.decide(for: frame(isCanvasOnly: false), at: changedAt + 0.1),
            .init(allowed: false, crop: crop)
        )
        XCTAssertEqual(
            try context.decide(for: frame(isCanvasOnly: false), at: changedAt + FrameGate.recrop),
            .init(allowed: true, crop: crop)
        )
    }

    func testAScreenFrameWithALayoutIsHeldWhileAnOverlayIsShown() throws {
        let context = CaptureContext()
        context.setLayout(layout(), at: 0)
        context.overlay(.settings, shown: true, at: 0)
        XCTAssertEqual(
            try context.decide(for: frame(isCanvasOnly: false), at: 1),
            .init(allowed: false, crop: CanvasRect(x: 0, y: 0, width: 40, height: 30))
        )
    }

    func testALayoutWithNoShareableAreaIsHeld() throws {
        let context = CaptureContext()
        let canvas = CGRect(x: 0, y: 0, width: 400, height: 300)
        context.setLayout(layout(canvas: canvas, obstructions: [canvas]), at: 0)
        XCTAssertEqual(
            try context.decide(for: frame(isCanvasOnly: false), at: 1),
            .init(allowed: false, crop: nil)
        )
    }

    private func layout(
        canvas: CGRect = CGRect(x: 0, y: 0, width: 400, height: 300),
        obstructions: [CGRect] = []
    ) -> CanvasLayout {
        CanvasLayout(
            canvas: canvas,
            window: CGSize(width: 400, height: 300),
            obstructions: obstructions
        )
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

final class CaptureLaunchTests: XCTestCase {
    private func defaults(_ values: [String: Any]) throws -> UserDefaults {
        let name = "CaptureLaunchTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        values.forEach { defaults.set($1, forKey: $0) }
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: name) }
        return defaults
    }

    func testNoSourceMeansNoSpike() throws {
        XCTAssertNil(try CaptureLaunch.current(defaults([:])))
    }

    func testAMistypedSourceIsRefusedRatherThanRunningReplayKit() throws {
        XCTAssertNil(try CaptureLaunch.current(defaults(["captureSource": "hierachy"])))
    }

    func testReplayKitRunsTheProbeWithoutARenderer() throws {
        let launch = try XCTUnwrap(CaptureLaunch.current(defaults(["captureSource": "replayKit"])))
        XCTAssertNil(launch.method)
        XCTAssertEqual(launch.scale, 1)
    }

    func testARendererSourceKeepsItsScale() throws {
        let launch = try XCTUnwrap(CaptureLaunch.current(
            defaults(["captureSource": "layer", "captureScale": 0.5])
        ))
        XCTAssertEqual(launch.method, .layer)
        XCTAssertEqual(launch.scale, 0.5)
    }
}
