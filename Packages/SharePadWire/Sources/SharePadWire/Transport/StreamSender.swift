import CoreMedia
import CoreVideo
import Foundation
import Network
import os

// @unchecked: all state lives on `queue`. The browser and connection are started
// on it, so Network.framework's callbacks (send completions included) land there
// too; only the encoder's output hops in explicitly.
public final class StreamSender: @unchecked Sendable {
    private let onPhase: @Sendable (SenderLink.Phase) -> Void
    private let onStats: @Sendable (Stats) -> Void
    private let onLocalNetworkDenied: @Sendable (Bool) -> Void
    private let onPairedEvent: @Sendable (PairedEvent) -> Void

    private let identity: Hello
    private let encoder: H264Encoder
    private let queue = DispatchQueue(label: "co.sharepad.wire.sender")
    private let log = Logger(subsystem: "co.sharepad.wire", category: "sender")
    private var link: SenderLink
    private var rules = SenderRules()
    private var frameRate = FrameRateEstimator()
    private var browser: WireBrowser?
    private var connection: WireConnection?
    private var endpoints: [String: NWEndpoint] = [:]
    private var security: Security
    private var lastResults: [NWBrowser.Result] = []
    private var pairedServices: [String: PairingRecord] = [:]
    private var dialled: PairingRecord?
    private var isStreaming = false
    private var canvas: CanvasRect?
    private var lastConfig: StreamConfig?
    private var sequence: UInt32 = 0
    private var nextHandoffID: UInt64 = 0
    private var captureTimes: [Double: Double] = [:]
    private var meter = RateMeter()
    private var stats = Stats()
    private var encodeTimes = MeanMeter()

    public init(
        deviceID: UUID,
        deviceName: String,
        settings: EncoderSettings = EncoderSettings(),
        lastPeer: String? = nil,
        security: Security = .unauthenticated,
        onPhase: @escaping @Sendable (SenderLink.Phase) -> Void = { _ in },
        onStats: @escaping @Sendable (Stats) -> Void = { _ in },
        onLocalNetworkDenied: @escaping @Sendable (Bool) -> Void = { _ in },
        onPairedEvent: @escaping @Sendable (PairedEvent) -> Void = { _ in }
    ) {
        self.onPhase = onPhase
        self.onStats = onStats
        self.onLocalNetworkDenied = onLocalNetworkDenied
        self.onPairedEvent = onPairedEvent
        self.security = security
        identity = Hello(deviceID: deviceID, deviceName: deviceName)
        encoder = H264Encoder(settings: settings)
        link = SenderLink(lastPeer: lastPeer)
        encoder.onEncodedFrame = { [weak self] frame in
            guard let self else { return }
            queue.async { self.handleEncoded(frame) }
        }
    }

    public func start() {
        queue.async { [weak self] in self?.send(.start) }
    }

    public func stop() {
        queue.async { [weak self] in self?.send(.stop) }
    }

    public func setCanvas(_ rect: CanvasRect?) {
        queue.async { [weak self] in
            guard let self, rect != canvas else { return }
            canvas = rect
            _ = rules.reduce(.keyframeRequested)
        }
    }

    public func submit(
        pixelBuffer: CVPixelBuffer,
        presentationTime: CMTime,
        captureWallClock: Double
    ) {
        nonisolated(unsafe) let pixelBuffer = pixelBuffer
        queue.async { [weak self] in
            self?.capture(
                pixelBuffer,
                presentationTime: presentationTime,
                wallClock: captureWallClock
            )
        }
    }

    // ── Link ──

    private func send(_ event: SenderLink.Event) {
        let effects = link.reduce(event)
        effects.forEach(perform)
        let phase = link.phase
        let onPhase = onPhase
        DispatchQueue.main.async { onPhase(phase) }
    }

    private func perform(_ effect: SenderLink.Effect) {
        switch effect {
        case .startBrowsing:
            startBrowsing()
        case .stopBrowsing:
            browser?.cancel()
            browser = nil
        case let .connect(name):
            connect(to: name)
        case let .scheduleConnectTimeout(attempt, delay):
            queue.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.send(.connectTimedOut(attempt: attempt))
            }
        case let .scheduleRetry(delay):
            queue.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.send(.retryElapsed)
            }
        case .closeConnection:
            connection?.cancel()
            connection = nil
            dialled = nil
        case .sendHello:
            sendHello()
        case .startStreaming, .pauseStreaming, .resumeStreaming, .stopStreaming:
            performStreaming(effect)
        }
    }

    private func performStreaming(_ effect: SenderLink.Effect) {
        switch effect {
        case .startStreaming:
            isStreaming = true
            _ = rules.reduce(.linkStarted)
            lastConfig = nil
            captureTimes = [:]
        case .pauseStreaming:
            _ = rules.reduce(.paused)
        case .resumeStreaming:
            _ = rules.reduce(.resumed)
        case .stopStreaming:
            isStreaming = false
            encoder.invalidate()
        default:
            break
        }
    }

    private func open(_ connection: WireConnection) {
        self.connection = connection
        connection.onEvent = { [weak self, weak connection] event in
            guard let self, let connection, connection === self.connection else { return }
            handle(event)
        }
        connection.start()
    }

    private func handle(_ event: WireConnection.Event) {
        switch event {
        case .ready:
            send(.connectionReady)
        case let .message(message):
            handle(message)
        case let .waiting(error) where error.isLinkAuthenticationFailure:
            handshakeFailed()
        case let .waiting(error):
            log.info("waiting: \(String(describing: error))")
        case let .failed(error) where error?.isLinkAuthenticationFailure == true:
            handshakeFailed()
        case .failed, .cancelled:
            connection = nil
            dialled = nil
            send(.connectionLost)
        }
    }

    private func handle(_ message: WireMessage) {
        switch message {
        case let .hello(hello):
            helloReceived(hello)
        case .requestKeyframe:
            _ = rules.reduce(.keyframeRequested)
        case .pause:
            send(.pauseReceived)
        case .resume:
            send(.resumeReceived)
        case let .ping(t1):
            connection?.send(.pong(t1: t1, t2: Date().timeIntervalSince1970))
        case .config, .frame, .pong:
            break
        }
    }

    // ── Frames ──

    private func capture(
        _ pixelBuffer: CVPixelBuffer,
        presentationTime: CMTime,
        wallClock: Double
    ) {
        guard isStreaming else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if let rate = frameRate.rateToApply(afterCaptureAt: now) {
            encoder.updateExpectedFrameRate(rate)
        }
        let effects = rules.reduce(.frameCaptured(at: now, encodesInFlight: encoder.pendingFrames))
        for effect in effects {
            switch effect {
            case let .encode(forceKeyframe):
                captureTimes[presentationTime.seconds] = wallClock
                if captureTimes.count > 240 {
                    let cutoff = presentationTime.seconds - 4
                    captureTimes = captureTimes.filter { $0.key > cutoff }
                }
                encoder.encode(
                    pixelBuffer: pixelBuffer,
                    presentationTime: presentationTime,
                    forceKeyframe: forceKeyframe
                )
            case .skip:
                stats.skippedFrames += 1
            }
        }
    }

    private func handleEncoded(_ frame: H264Encoder.EncodedFrame) {
        guard isStreaming, let connection else { return }
        if frame.isKeyframe {
            _ = rules.reduce(.keyframeEncoded)
            stats.keyframes += 1
            let config = StreamConfig(
                width: frame.width,
                height: frame.height,
                canvas: canvas ?? .whole(width: frame.width, height: frame.height),
                parameterSets: frame.parameterSets
            )
            if !frame.parameterSets.isEmpty, config != lastConfig {
                connection.send(.config(config))
                lastConfig = config
            }
        }

        let wallClock = captureTimes.removeValue(forKey: frame.presentationTime.seconds)
        if let wallClock { encodeTimes.record(Date().timeIntervalSince1970 - wallClock) }
        sequence &+= 1
        nextHandoffID &+= 1
        let id = nextHandoffID
        _ = rules.reduce(.frameHandedOff(id: id, at: ProcessInfo.processInfo.systemUptime))
        connection.send(.frame(EncodedVideoFrame(
            sequence: sequence,
            isKeyframe: frame.isKeyframe,
            captureWallClock: wallClock,
            avcc: frame.avcc
        ))) { [weak self] in
            _ = self?.rules.reduce(.frameSent(id: id))
        }

        stats.encodedFrames += 1
        meter.record(bytes: frame.avcc.count)
        if meter.tick() {
            stats.framesPerSecond = meter.eventsPerSecond
            stats.kilobitsPerSecond = meter.bytesPerSecond * 8 / 1000
            stats.interface = connection.interfaceSummary
            stats.encodeMilliseconds = encodeTimes.takeMean() * 1000
            let snapshot = stats
            let onStats = onStats
            DispatchQueue.main.async { onStats(snapshot) }
        }
    }
}

public extension StreamSender {
    func setPairings(_ records: [PairingRecord]) {
        queue.async { [weak self] in self?.pairingsChanged(records) }
    }
}

private extension StreamSender {
    func found(_ results: [NWBrowser.Result]) {
        lastResults = results
        let all = Dictionary(
            results.map { ($0.serviceName, $0.endpoint) },
            uniquingKeysWith: { first, _ in first }
        )
        guard case let .paired(records) = security else {
            endpoints = all
            send(.found(results.map(\.serviceName)))
            return
        }
        let ranked = PairedServices.rank(
            results.map { AdvertisedService(name: $0.serviceName, deviceID: $0.deviceID) },
            pairings: records
        )
        pairedServices = Dictionary(
            ranked.map { ($0.name, $0.record) },
            uniquingKeysWith: { first, _ in first }
        )
        endpoints = all.filter { pairedServices[$0.key] != nil }
        send(.found(ranked.map(\.name)))
    }

    func connect(to name: String) {
        guard let endpoint = endpoints[name] else {
            send(.connectionLost)
            return
        }
        switch security {
        case .unauthenticated:
            dialled = nil
            open(WireConnection.outbound(to: endpoint, queue: queue))
        case .paired:
            guard let record = pairedServices[name] else {
                send(.connectionLost)
                return
            }
            dialled = record
            open(WireConnection.outbound(to: endpoint, security: .paired(record), queue: queue))
        }
    }

    func sendHello() {
        guard let connection else { return }
        if let dialled {
            guard let exporter = connection.linkExporter() else {
                dropConnection()
                return
            }
            connection.send(.authenticate(.paired(dialled, exporter: exporter)))
        }
        connection.send(.hello(identity))
    }

    func helloReceived(_ hello: Hello) {
        if let dialled {
            guard hello.deviceID == dialled.peerID else {
                dropConnection()
                return
            }
            report(.connected(macID: dialled.peerID))
        }
        send(.helloReceived(hello))
    }

    func handshakeFailed() {
        if let dialled { report(.handshakeFailed(macID: dialled.peerID)) }
        dropConnection()
    }

    func dropConnection() {
        connection?.cancel()
        connection = nil
        dialled = nil
        send(.connectionLost)
    }

    func report(_ event: PairedEvent) {
        let onPairedEvent = onPairedEvent
        DispatchQueue.main.async { onPairedEvent(event) }
    }

    // Forgetting the Mac this link is on tells it first, best effort, so its row can
    // read "Needs pairing again" (specs/wireless-pairing-ui.md, decision 2).
    func pairingsChanged(_ records: [PairingRecord]) {
        guard case .paired = security else { return }
        security = .paired(records)
        if let dialled, !records.contains(where: { $0.pairingID == dialled.pairingID }) {
            let forgotten = connection
            connection = nil
            self.dialled = nil
            forgotten?.send(.forgotten(pairingID: dialled.pairingID)) { forgotten?.cancel() }
            send(.connectionLost)
        }
        found(lastResults)
    }

    func startBrowsing() {
        browser?.cancel()
        let browser = WireBrowser()
        browser.onResults = { [weak self] results in self?.found(results) }
        let onDenied = onLocalNetworkDenied
        browser.onLocalNetworkDenied = { denied in
            DispatchQueue.main.async { onDenied(denied) }
        }
        browser.start(queue: queue)
        self.browser = browser
    }
}
