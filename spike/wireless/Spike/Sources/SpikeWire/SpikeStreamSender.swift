import CoreMedia
import CoreVideo
import Foundation
import Network

/// Everything the sending side needs bar the frame source: discover a receiver,
/// encode, and push. Shared by the iPad ReplayKit app and the macOS fake sender
/// so both exercise the identical transport path.
public final class SpikeStreamSender {
    public enum State {
        case idle
        case browsing
        case connecting(String)
        case streaming(String)
        case failed(String)

        public var label: String {
            switch self {
            case .idle: "idle"
            case .browsing: "looking for a Mac…"
            case let .connecting(name): "connecting to \(name)…"
            case let .streaming(name): "streaming to \(name)"
            case let .failed(reason): "failed: \(reason)"
            }
        }
    }

    public struct Stats {
        public var framesPerSecond: Double = 0
        public var kilobitsPerSecond: Double = 0
        public var droppedFrames = 0
        public var encodedFrames = 0
    }

    public var onState: ((State) -> Void)?
    public var onStats: ((Stats) -> Void)?

    private let encoder: H264Encoder
    private let queue = DispatchQueue(label: "spike.sender")
    private var browser: SpikeBrowser?
    private var connection: SpikeConnection?
    private var peerName = ""
    private var sequence: UInt32 = 0
    private var captureTimes: [Int64: Double] = [:]
    private var lastParameterSets: [Data] = []
    private var meter = RateMeter()
    private var stats = Stats()
    private var isStreaming = false
    private var encoderDrops = 0

    public init(bitrate: Int = 8_000_000, expectedFrameRate: Int = 15) {
        encoder = H264Encoder(bitrate: bitrate, expectedFrameRate: expectedFrameRate)
        encoder.onEncodedFrame = { [weak self] frame in
            self?.queue.async { self?.handleEncoded(frame) }
        }
    }

    public var isConnected: Bool {
        isStreaming
    }

    public func connect() {
        queue.async { [weak self] in
            guard let self, connection == nil else { return }
            report(.browsing)
            let browser = SpikeBrowser()
            browser.onResults = { [weak self] results in
                self?.queue.async { self?.handleResults(results) }
            }
            browser.start(queue: queue)
            self.browser = browser
        }
    }

    public func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            isStreaming = false
            browser?.cancel()
            browser = nil
            connection?.cancel()
            connection = nil
            lastParameterSets = []
            captureTimes = [:]
            encoder.invalidate()
            report(.idle)
        }
    }

    public func submit(
        pixelBuffer: CVPixelBuffer,
        presentationTime: CMTime,
        captureWallClock: Double
    ) {
        queue.async { [weak self] in
            guard let self, isStreaming else { return }
            // The first VTCompressionSession creation costs ~1.8 s on a cold
            // process; unbounded, the frame source keeps submitting and the
            // backlog drains as a burst of stale frames reading ~1.8 s late.
            // Capping in-flight encodes keeps the measured latency the real one.
            guard encoder.pendingFrames < 3 else {
                encoderDrops += 1
                return
            }
            captureTimes[presentationTime.value] = captureWallClock
            if captureTimes.count > 240 {
                // Frames the encoder never emitted (dropped internally) would leak.
                let cutoff = presentationTime.value - Int64(presentationTime.timescale) * 4
                captureTimes = captureTimes.filter { $0.key > cutoff }
            }
            encoder.encode(pixelBuffer: pixelBuffer, presentationTime: presentationTime)
        }
    }

    private func handleResults(_ results: [NWBrowser.Result]) {
        guard connection == nil, let first = results.first else { return }
        // Spike-level pairing: first service wins. specs/wireless.md flags
        // pick-and-confirm as unresolved product design, not a latency question.
        if results.count > 1 {
            print("[sender] \(results.count) receivers visible, taking \(first.displayName)")
        }
        peerName = first.displayName
        report(.connecting(peerName))

        let connection = SpikeConnection.outbound(to: first.endpoint, queue: queue)
        connection.onEvent = { [weak self] event in
            self?.handle(event)
        }
        self.connection = connection
        connection.start()
    }

    private func handle(_ event: SpikeConnection.Event) {
        switch event {
        case .ready:
            isStreaming = true
            lastParameterSets = []
            browser?.cancel()
            browser = nil
            report(.streaming(peerName))
        case let .message(message):
            if case let .ping(t1) = message {
                connection?.send(.pong(t1: t1, t2: Date().timeIntervalSince1970))
            }
        case let .waiting(error):
            report(.connecting("\(peerName) (\(error.localizedDescription))"))
        case let .failed(error):
            isStreaming = false
            connection = nil
            report(.failed(error?.localizedDescription ?? "connection closed"))
            connect()
        case .cancelled:
            isStreaming = false
        }
    }

    private func handleEncoded(_ frame: H264Encoder.EncodedFrame) {
        guard isStreaming, let connection else { return }

        if frame.isKeyframe, !frame.parameterSets.isEmpty,
           frame.parameterSets != lastParameterSets {
            connection.send(.config(
                width: frame.width,
                height: frame.height,
                parameterSets: frame.parameterSets
            ))
            lastParameterSets = frame.parameterSets
        }

        // 0 means "capture time unknown", which the receiver reads as a frame it
        // must not draw a latency sample from. A wall-clock fallback here would
        // silently report a near-zero latency for that frame instead.
        let captureWallClock = captureTimes.removeValue(forKey: frame.presentationTime.value) ?? 0
        sequence += 1
        // Keyframes are never dropped: losing one strands the decoder for up to
        // the keyframe interval.
        connection.send(
            .frame(SpikeFrame(
                sequence: sequence,
                isKeyframe: frame.isKeyframe,
                captureWallClock: captureWallClock,
                avcc: frame.avcc
            )),
            droppable: !frame.isKeyframe
        )

        stats.encodedFrames += 1
        stats.droppedFrames = encoderDrops + connection.droppedFrames
        meter.record(bytes: frame.avcc.count)
        if meter.tick() {
            stats.framesPerSecond = meter.eventsPerSecond
            stats.kilobitsPerSecond = meter.bytesPerSecond * 8 / 1000
            let snapshot = stats
            DispatchQueue.main.async { [weak self] in self?.onStats?(snapshot) }
        }
    }

    private func report(_ state: State) {
        print("[sender] \(state.label)")
        DispatchQueue.main.async { [weak self] in self?.onState?(state) }
    }
}
