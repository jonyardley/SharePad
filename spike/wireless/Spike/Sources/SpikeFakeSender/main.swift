import AppKit
import CoreMedia
import CoreVideo
import SpikeWire

// Stand-in for the iPad, so the transport, encode, decode and render path can be
// proved on one Mac without hardware. It draws the same millisecond counter the
// iPad app shows, which is what makes a decoded snapshot readable evidence.

struct Options {
    var width = 1280
    var height = 800
    var fps = 15
    var bitrate = 8_000_000
    var seconds: Double?

    static func parse(_ arguments: [String]) -> Options {
        var options = Options()
        var index = 0
        while index < arguments.count {
            let value: String? = index + 1 < arguments.count ? arguments[index + 1] : nil
            switch arguments[index] {
            case "--width":
                options.width = value.flatMap(Int.init) ?? options.width
                index += 1
            case "--height":
                options.height = value.flatMap(Int.init) ?? options.height
                index += 1
            case "--fps":
                options.fps = value.flatMap(Int.init) ?? options.fps
                index += 1
            case "--bitrate":
                options.bitrate = value.flatMap(Int.init) ?? options.bitrate
                index += 1
            case "--seconds":
                options.seconds = value.flatMap(Double.init)
                index += 1
            case "--help":
                print("spike-fakesender [--width n] [--height n] [--fps n]")
                print("                 [--bitrate bps] [--seconds n]")
                exit(0)
            default:
                break
            }
            index += 1
        }
        return options
    }
}

final class FrameSource {
    private let width: Int
    private let height: Int
    private let fps: Int
    private var pool: CVPixelBufferPool?
    private let startedAt = Date().timeIntervalSince1970

    init(width: Int, height: Int, fps: Int) {
        self.width = width
        self.height = height
        self.fps = fps

        let poolAttributes: [String: Any] = [kCVPixelBufferPoolMinimumBufferCountKey as String: 4]
        let bufferAttributes: [String: Any] = [
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:] as CFDictionary,
        ]
        var created: CVPixelBufferPool?
        CVPixelBufferPoolCreate(
            kCFAllocatorDefault,
            poolAttributes as CFDictionary,
            bufferAttributes as CFDictionary,
            &created
        )
        pool = created
    }

    func nextFrame(index: Int) -> CVPixelBuffer? {
        guard let pool else { return nil }
        var buffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &buffer) ==
            kCVReturnSuccess,
            let buffer
        else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer),
              let context = CGContext(
                  data: base,
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
                      | CGBitmapInfo.byteOrder32Little.rawValue
              )
        else { return nil }

        let elapsedMs = (Date().timeIntervalSince1970 - startedAt) * 1000
        draw(in: context, elapsedMs: elapsedMs, index: index)
        return buffer
    }

    private func draw(in context: CGContext, elapsedMs: Double, index: Int) {
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        context.setFillColor(NSColor.white.cgColor)
        context.fill(bounds)

        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        defer { NSGraphicsContext.current = previous }

        let counter = String(format: "%08.1f ms", elapsedMs)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 140, weight: .bold),
            .foregroundColor: NSColor.black,
        ]
        let size = counter.size(withAttributes: attributes)
        counter.draw(
            at: NSPoint(
                x: (CGFloat(width) - size.width) / 2,
                y: CGFloat(height) / 2 - size.height / 2
            ),
            withAttributes: attributes
        )

        // A sweeping bar gives motion the encoder has to work on, so the bitrate
        // is not the trivial static-screen case.
        let sweep = CGFloat(index % max(fps, 1)) / CGFloat(max(fps, 1))
        context.setFillColor(NSColor.systemRed.cgColor)
        context.fill(CGRect(x: sweep * CGFloat(width), y: 0, width: 24, height: CGFloat(height)))

        let label = "spike-fakesender frame \(index)"
        label.draw(at: NSPoint(x: 24, y: CGFloat(height) - 48), withAttributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 24, weight: .regular),
            .foregroundColor: NSColor.darkGray,
        ])
    }
}

let options = Options.parse(Array(CommandLine.arguments.dropFirst()))
let source = FrameSource(width: options.width, height: options.height, fps: options.fps)
let sender = SpikeStreamSender(bitrate: options.bitrate, expectedFrameRate: options.fps)

sender.onStats = { stats in
    print(String(
        format: "[fakesender] %.1f fps, %.0f kbps, %d encoded, %d dropped",
        stats.framesPerSecond, stats.kilobitsPerSecond, stats.encodedFrames, stats.droppedFrames
    ))
}

sender.connect()

let timerQueue = DispatchQueue(label: "spike.fakesender.frames")
let timer = DispatchSource.makeTimerSource(queue: timerQueue)
var frameIndex = 0
timer.schedule(deadline: .now(), repeating: 1.0 / Double(options.fps), leeway: .milliseconds(2))
timer.setEventHandler {
    guard let pixelBuffer = source.nextFrame(index: frameIndex) else { return }
    let capturedAt = Date().timeIntervalSince1970
    sender.submit(
        pixelBuffer: pixelBuffer,
        presentationTime: CMTime(value: Int64(frameIndex), timescale: CMTimeScale(options.fps)),
        captureWallClock: capturedAt
    )
    frameIndex += 1
}

timer.resume()

if let seconds = options.seconds {
    DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
        timer.cancel()
        sender.stop()
        print("[fakesender] sent \(frameIndex) frames over \(seconds)s")
        exit(0)
    }
}

RunLoop.main.run()
