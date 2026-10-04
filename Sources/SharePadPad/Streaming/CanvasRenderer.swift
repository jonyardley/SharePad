#if DEBUG
    import CoreMedia
    import CoreVideo
    import SwiftUI
    import UIKit

    // Replaces ReplayKit so the app never asks to record (specs/canvas-render-spike.md).
    enum CanvasSnapshotMethod: String {
        case hierarchy
        case layer
    }

    struct CaptureLaunch {
        let source: String
        let method: CanvasSnapshotMethod?
        let scale: CGFloat

        static let replayKit = "replayKit"

        static func current(_ defaults: UserDefaults = .standard) -> CaptureLaunch? {
            guard let source = defaults.string(forKey: "captureSource") else { return nil }
            let method = CanvasSnapshotMethod(rawValue: source)
            guard method != nil || source == replayKit else { return nil }
            let scale = defaults.double(forKey: "captureScale")
            return CaptureLaunch(
                source: source,
                method: method,
                scale: scale > 0 ? scale : 1
            )
        }
    }

    @MainActor
    struct CaptureSpike {
        let probe: CaptureProbe
        let sampler: ProbeSampler
        let renderer: CanvasRenderer?

        static func fromLaunch(canvas: CanvasController, paper: Paper) -> CaptureSpike? {
            guard let launch = CaptureLaunch.current(),
                  let probe = CaptureProbe(source: launch.source) else { return nil }
            let renderer = launch.method.map {
                CanvasRenderer(canvas: canvas, method: $0, scale: launch.scale, paper: paper)
            }
            renderer?.onRendered = { probe.rendered($0) }
            return CaptureSpike(
                probe: probe,
                sampler: ProbeSampler(probe: probe),
                renderer: renderer
            )
        }
    }

    @MainActor
    final class CanvasRenderer: ScreenRecording {
        var paper: Paper
        var onRendered: ((_ milliseconds: Double) -> Void)?

        private struct PaperKey: Equatable {
            let paper: Paper
            let viewport: Viewport
            let size: CGSize
            let scale: CGFloat
        }

        private let canvas: CanvasController
        private let method: CanvasSnapshotMethod
        private let scale: CGFloat
        private var onFrame: (@Sendable (CapturedFrame) -> Void)?
        private var pool: CVPixelBufferPool?
        private var poolWidth = 0
        private var poolHeight = 0
        private var paperImage: (key: PaperKey, image: CGImage)?

        init(canvas: CanvasController, method: CanvasSnapshotMethod, scale: CGFloat, paper: Paper) {
            self.canvas = canvas
            self.method = method
            self.scale = scale
            self.paper = paper
        }

        func start(
            onFrame: @escaping @Sendable (CapturedFrame) -> Void,
            completion: @escaping @MainActor @Sendable (Bool) -> Void
        ) {
            self.onFrame = onFrame
            canvas.onFrameTick = { [weak self] in self?.render() }
            completion(true)
        }

        func stop(completion: @escaping @MainActor @Sendable () -> Void) {
            canvas.onFrameTick = nil
            onFrame = nil
            completion()
        }

        private func render() {
            guard let onFrame else { return }
            let size = canvas.canvasSize
            let pixelScale = canvas.displayScale * scale
            let width = Int((size.width * pixelScale).rounded())
            let height = Int((size.height * pixelScale).rounded())
            guard width > 0, height > 0, let buffer = makeBuffer(width: width, height: height)
            else { return }

            let time = CMClockGetTime(CMClockGetHostTimeClock())
            let started = CACurrentMediaTime()
            guard draw(into: buffer, size: size, pixelScale: pixelScale) else { return }
            onRendered?((CACurrentMediaTime() - started) * 1000)
            onFrame(CapturedFrame(
                pixelBuffer: buffer,
                presentationTime: time,
                orientation: .up,
                isCanvasOnly: true
            ))
        }

        private func draw(into buffer: CVPixelBuffer, size: CGSize, pixelScale: CGFloat) -> Bool {
            CVPixelBufferLockBaseAddress(buffer, [])
            defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
            let width = CVPixelBufferGetWidth(buffer)
            let height = CVPixelBufferGetHeight(buffer)
            guard let context = CGContext(
                data: CVPixelBufferGetBaseAddress(buffer),
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                    | CGBitmapInfo.byteOrder32Little.rawValue
            ) else { return false }

            context.clear(CGRect(x: 0, y: 0, width: width, height: height))
            if let paper = paperImage(size: size, pixelScale: pixelScale) {
                context.draw(paper, in: CGRect(x: 0, y: 0, width: width, height: height))
            }
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: pixelScale, y: -pixelScale)
            canvas.drawCanvas(in: context, method: method)
            return true
        }

        private func paperImage(size: CGSize, pixelScale: CGFloat) -> CGImage? {
            let key = PaperKey(
                paper: paper,
                viewport: canvas.viewport,
                size: size,
                scale: pixelScale
            )
            if let paperImage, paperImage.key == key { return paperImage.image }
            let renderer = ImageRenderer(
                content: PaperBackground(paper: paper, viewport: key.viewport)
                    .frame(width: size.width, height: size.height)
            )
            renderer.scale = pixelScale
            guard let image = renderer.cgImage else { return nil }
            paperImage = (key, image)
            return image
        }

        private func makeBuffer(width: Int, height: Int) -> CVPixelBuffer? {
            if pool == nil || width != poolWidth || height != poolHeight {
                let attributes: [CFString: Any] = [
                    kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
                    kCVPixelBufferWidthKey: width,
                    kCVPixelBufferHeightKey: height,
                    kCVPixelBufferIOSurfacePropertiesKey: [CFString: Any](),
                    kCVPixelBufferCGBitmapContextCompatibilityKey: true,
                ]
                var created: CVPixelBufferPool?
                CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &created)
                pool = created
                poolWidth = width
                poolHeight = height
            }
            guard let pool else { return nil }
            // A full pool means the encoder is behind; dropping here beats growing it.
            let limit = [kCVPixelBufferPoolAllocationThresholdKey: 8] as CFDictionary
            var buffer: CVPixelBuffer?
            let status = CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(
                nil,
                pool,
                limit,
                &buffer
            )
            return status == kCVReturnSuccess ? buffer : nil
        }
    }
#endif
