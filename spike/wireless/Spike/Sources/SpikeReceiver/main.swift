import AppKit
import AVFoundation
import SharePadWire

// Mac receiver for the wireless spike (specs/wireless.md). Streams from one
// sender at a time and parks others on standby, decodes H.264, renders into a
// plain window, and reports the latency numbers the go/kill call needs.

struct Options {
    var serviceName = Host.current().localizedName ?? "SharePad Spike"
    var csvPath: String?
    var snapshotPath: String?
    var snapshotAfterFrames = 30
    var exitAfter: Double?
    var headless = false

    static func parse(_ arguments: [String]) -> Options {
        var options = Options()
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            let value: String? = index + 1 < arguments.count ? arguments[index + 1] : nil
            switch argument {
            case "--name":
                options.serviceName = value ?? options.serviceName
                index += 1
            case "--csv":
                options.csvPath = value
                index += 1
            case "--snapshot":
                options.snapshotPath = value
                index += 1
            case "--snapshot-after":
                options.snapshotAfterFrames = value.flatMap(Int.init) ?? options.snapshotAfterFrames
                index += 1
            case "--exit-after":
                options.exitAfter = value.flatMap(Double.init)
                index += 1
            case "--headless":
                options.headless = true
            case "--help":
                print("""
                spike-receiver [--name <bonjour name>] [--csv <path>] [--snapshot <path.png>]
                               [--snapshot-after <frames>] [--exit-after <seconds>] [--headless]
                """)
                exit(0)
            default:
                break
            }
            index += 1
        }
        return options
    }
}

final class Receiver {
    let displayLayer = AVSampleBufferDisplayLayer()
    var onHUD: ((String) -> Void)?

    private let options: Options
    private let decoder = H264Decoder()
    private var clock = ClockSync()
    private let queue = DispatchQueue(label: "spike.receiver")
    private let identity = Hello(
        deviceID: UUID(),
        deviceName: Host.current().localizedName ?? "Mac"
    )
    private var listener: WireListener?
    private var connections: [ConnectionID: WireConnection] = [:]
    private var nextConnectionID = 0
    private var link = ReceiverLink()
    private var keyframes = KeyframeRequester()
    private var keyframeRequests = 0
    private var keyframesReceived = 0

    private var latencyMs = RollingStats()
    private var decodeMs = RollingStats()
    private var intervalMs = RollingStats()
    private var meter = RateMeter()
    private var framesPerSecond: Double = 0
    private var kilobitsPerSecond: Double = 0
    private var frameCount = 0
    private var undecodableFrames = 0
    private var lastArrival: Double?
    private var dimensions = "—"
    private var peer = "waiting for a sender"
    private var path = "no path"
    private var csv: FileHandle?
    private var snapshotWritten = false
    private var startedAt = Date().timeIntervalSince1970
    private var pendingMeta: [UInt32: (bytes: Int, keyframe: Bool, interval: Double)] = [:]
    private var hudPrints = 0

    init(options: Options) {
        self.options = options
        decoder.onDecodedFrame = { [weak self] frame in
            self?.handleDecoded(frame)
        }
        decoder.onDecodeFailed = { [weak self] _ in
            guard let self else { return }
            queue.async { [weak self] in
                guard let self else { return }
                request(keyframes.reduce(.decodeFailed(at: uptime)))
            }
        }
        if let path = options.csvPath {
            FileManager.default.createFile(atPath: path, contents: nil)
            csv = FileHandle(forWritingAtPath: path)
            write(csvLine: "seq,recv_wall,latency_ms,latency_valid," +
                "decode_ms,interval_ms,bytes,keyframe")
        }
    }

    func start() {
        do {
            let listener = try WireListener(serviceName: options.serviceName, queue: queue)
            listener.onStateChange = { [weak self] state in
                guard let self else { return }
                if case .ready = state {
                    let port = listener.port.map(String.init) ?? "?"
                    print("[receiver] advertising “\(options.serviceName)” on port \(port)")
                }
                if case let .failed(error) = state {
                    print("[receiver] listener failed: \(error)")
                }
            }
            listener.onConnection = { [weak self] connection in
                self?.accept(connection)
            }
            listener.start()
            self.listener = listener
        } catch {
            print("[receiver] could not listen: \(error)")
            exit(1)
        }

        queue.asyncAfter(deadline: .now() + 1) { [weak self] in self?.sendPing() }
        // Every stat lives on `queue`, so the HUD is built there too and only the
        // finished string crosses to main. A main-thread timer reading the stats
        // directly would race the decode callbacks that write them.
        queue.asyncAfter(deadline: .now() + 0.25) { [weak self] in self?.publishHUD() }
        if let seconds = options.exitAfter {
            queue.asyncAfter(deadline: .now() + seconds) { [weak self] in
                self?.finish()
            }
        }
    }

    private var uptime: TimeInterval {
        ProcessInfo.processInfo.systemUptime
    }

    private var active: WireConnection? {
        guard case let .live(current) = link.phase else { return nil }
        return connections[current.connection]
    }

    private func accept(_ connection: WireConnection) {
        nextConnectionID += 1
        let id = nextConnectionID
        connections[id] = connection
        connection.onEvent = { [weak self] event in
            self?.handle(event, from: id)
        }
        connection.start()
    }

    private func handle(_ event: WireConnection.Event, from id: ConnectionID) {
        switch event {
        case .ready:
            apply(link.reduce(.opened(id)))
        case let .message(message):
            handle(message, from: id)
        case let .failed(error):
            print("[receiver] connection \(id) closed (\(error?.localizedDescription ?? "eof"))")
            drop(id)
        case .cancelled:
            drop(id)
        case let .waiting(error):
            peer = "waiting (\(error.localizedDescription))"
        }
    }

    private func drop(_ id: ConnectionID) {
        guard connections.removeValue(forKey: id) != nil else { return }
        apply(link.reduce(.closed(id, at: uptime)))
    }

    private func apply(_ effects: [ReceiverLink.Effect]) {
        for effect in effects {
            switch effect {
            case let .sendHello(id):
                connections[id]?.send(.hello(identity))
            case let .close(id, reason):
                print("[receiver] closing connection \(id): \(reason)")
                connections.removeValue(forKey: id)?.cancel()
            case .adopt:
                if case let .live(current) = link.phase {
                    peer = current.hello.deviceName
                }
                startedAt = Date().timeIntervalSince1970
                print("[receiver] streaming from \(peer)")
                path = active?.interfaceSummary ?? "no path"
                print("[receiver] path: \(path)")
                request(keyframes.reduce(.connected(at: uptime)))
            case let .sendPause(id):
                print("[receiver] a second sender is on standby")
                connections[id]?.send(.pause)
            case let .sendResume(id):
                connections[id]?.send(.resume)
            case let .scheduleHoldCheck(after):
                peer = "reconnecting…"
                print("[receiver] link lost, holding for \(after)s")
                queue.asyncAfter(deadline: .now() + after) { [weak self] in
                    guard let self else { return }
                    apply(link.reduce(.holdElapsed(at: uptime)))
                }
            case .endShare:
                peer = "waiting for a sender"
                print("[receiver] hold expired, share ended")
            }
        }
    }

    @discardableResult
    private func request(_ effects: [KeyframeRequester.Effect]) -> Bool {
        var shouldDecode = false
        for effect in effects {
            switch effect {
            case .sendRequest:
                keyframeRequests += 1
                active?.send(.requestKeyframe)
            case .decode:
                shouldDecode = true
            case .discard:
                undecodableFrames += 1
            }
        }
        return shouldDecode
    }

    private func handle(_ message: WireMessage, from id: ConnectionID) {
        if case let .hello(hello) = message {
            apply(link.reduce(.helloReceived(id, hello)))
            return
        }
        guard case let .live(current) = link.phase, current.connection == id else { return }
        switch message {
        case let .config(config):
            dimensions = "\(config.width)x\(config.height)"
            decoder.configure(parameterSets: config.parameterSets)
            crop(to: config)
        case let .frame(frame):
            let arrival = Date().timeIntervalSince1970
            var interval: Double = 0
            if let last = lastArrival {
                interval = (arrival - last) * 1000
                intervalMs.add(interval)
            }
            lastArrival = arrival
            meter.record(bytes: frame.avcc.count)
            if meter.tick() {
                framesPerSecond = meter.eventsPerSecond
                kilobitsPerSecond = meter.bytesPerSecond * 8 / 1000
            }
            if frame.isKeyframe {
                keyframesReceived += 1
            }
            let arrived = keyframes.reduce(.frameArrived(isKeyframe: frame.isKeyframe, at: uptime))
            guard request(arrived), decoder.isConfigured else { return }
            pendingMeta[frame.sequence] = (frame.avcc.count, frame.isKeyframe, interval)
            if pendingMeta.count > 240 {
                pendingMeta = pendingMeta.filter { $0.key > frame.sequence &- 120 }
            }
            decoder.decode(frame: frame)
        case let .pong(t1, t2):
            clock.handlePong(t1: t1, t2: t2, t3: Date().timeIntervalSince1970)
        case .hello, .ping, .requestKeyframe, .pause, .resume:
            break
        }
    }

    private func sendPing() {
        active?.send(.ping(t1: Date().timeIntervalSince1970))
        queue.asyncAfter(deadline: .now() + 1) { [weak self] in self?.sendPing() }
    }

    // Unit rect, origin bottom left: macOS layers are not flipped. Aspect is not
    // corrected here; the real share window (W1) owns that.
    private func crop(to config: StreamConfig) {
        guard config.width > 0, config.height > 0 else { return }
        let width = Double(config.width)
        let height = Double(config.height)
        let canvas = config.canvas
        let rect = CGRect(
            x: Double(canvas.x) / width,
            y: 1 - Double(canvas.y + canvas.height) / height,
            width: Double(canvas.width) / width,
            height: Double(canvas.height) / height
        )
        let layer = displayLayer
        DispatchQueue.main.async { layer.contentsRect = rect }
    }

    private func handleDecoded(_ frame: H264Decoder.DecodedFrame) {
        let now = Date().timeIntervalSince1970
        let pixelBuffer = frame.pixelBuffer
        DispatchQueue.main.async { [weak self] in
            self?.enqueue(pixelBuffer)
        }
        // VideoToolbox calls this back on its own thread; the stats belong to
        // `queue` and are only ever touched there.
        queue.async { [weak self] in
            self?.record(frame: frame, arrivedAt: now)
        }
    }

    private func record(frame: H264Decoder.DecodedFrame, arrivedAt now: Double) {
        let latency = frame.captureWallClock.map { (now - ($0 - clock.offset)) * 1000 }
        let isValid = clock.isSynced && latency.map { $0 > -50 && $0 < 5000 } == true
        if isValid, let latency {
            latencyMs.add(latency)
        }
        decodeMs.add(frame.decodeSeconds * 1000)
        frameCount += 1

        let meta = pendingMeta.removeValue(forKey: frame.sequence)
        write(csvLine: [
            "\(frame.sequence)",
            String(format: "%.6f", now),
            String(format: "%.2f", latency ?? 0),
            isValid ? "1" : "0",
            String(format: "%.3f", frame.decodeSeconds * 1000),
            String(format: "%.2f", meta?.interval ?? 0),
            "\(meta?.bytes ?? 0)",
            (meta?.keyframe ?? false) ? "1" : "0",
        ].joined(separator: ","))

        if let path = options.snapshotPath, !snapshotWritten,
           frameCount >= options.snapshotAfterFrames {
            snapshotWritten = true
            writeSnapshot(frame.pixelBuffer, to: path)
        }
    }

    private func enqueue(_ pixelBuffer: CVPixelBuffer) {
        guard !options.headless else { return }
        if displayLayer.status == .failed {
            displayLayer.flush()
            queue.async { [weak self] in
                guard let self else { return }
                request(keyframes.reduce(.layerFlushed(at: uptime)))
            }
        }
        var format: CMVideoFormatDescription?
        guard CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &format
        ) == noErr, let format else { return }

        var timing = CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: .invalid,
            decodeTimeStamp: .invalid
        )
        var sampleBuffer: CMSampleBuffer?
        guard CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescription: format,
            sampleTiming: &timing,
            sampleBufferOut: &sampleBuffer
        ) == noErr, let sampleBuffer else { return }

        // Display immediately: any presentation-time scheduling would add latency
        // to the number this spike measures.
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(
            sampleBuffer,
            createIfNecessary: true
        ),
            CFArrayGetCount(attachments) > 0 {
            let dictionary = unsafeBitCast(
                CFArrayGetValueAtIndex(attachments, 0),
                to: CFMutableDictionary.self
            )
            CFDictionarySetValue(
                dictionary,
                Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                Unmanaged.passUnretained(kCFBooleanTrue).toOpaque()
            )
        }
        displayLayer.enqueue(sampleBuffer)
    }

    private func publishHUD() {
        let text = hudText()
        DispatchQueue.main.async { [weak self] in self?.onHUD?(text) }
        if hudPrints % 4 == 0, frameCount > 0 {
            print("[receiver] " + text.replacingOccurrences(of: "\n", with: " | "))
        }
        hudPrints += 1
        queue.asyncAfter(deadline: .now() + 0.25) { [weak self] in self?.publishHUD() }
    }

    private func hudText() -> String {
        func format(_ stats: RollingStats) -> String {
            guard let median = stats.median, let p95 = stats.p95 else { return "—" }
            let jitter = stats.medianAbsoluteDeviation ?? 0
            return String(format: "med %.0f  p95 %.0f  jitter ±%.0f", median, p95, jitter)
        }

        let clockLine = clock.isSynced
            ? String(
                format: "offset %+.1f ms, rtt %.1f ms",
                clock.offset * 1000,
                clock.roundTrip * 1000
            )
            : "syncing…"

        let pending = undecodableFrames > 0 ? " (\(undecodableFrames) pre-keyframe)" : ""
        let rate = String(
            format: "%.1f fps · %.0f kbps",
            framesPerSecond,
            kilobitsPerSecond
        )

        return [
            "\(peer) · \(path) · \(dimensions) · frames \(frameCount)\(pending)",
            "rate \(rate)",
            "capture→decoded (ms): \(format(latencyMs))",
            "frame interval (ms): \(format(intervalMs))",
            "decode (ms): \(format(decodeMs)) · clock \(clockLine)",
        ].joined(separator: "\n")
    }

    private func write(csvLine line: String) {
        guard let csv, let data = (line + "\n").data(using: .utf8) else { return }
        csv.write(data)
    }

    private func writeSnapshot(_ pixelBuffer: CVPixelBuffer, to path: String) {
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        let representation = NSBitmapImageRep(ciImage: image)
        guard let data = representation.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: URL(fileURLWithPath: path))
        print("[receiver] wrote decoded frame \(frameCount) to \(path)")
    }

    func finish() {
        queue.async { [weak self] in
            guard let self else { exit(0) }
            print("\n=== spike-receiver summary ===")
            print(hudText())
            if let median = latencyMs.median {
                print(String(
                    format: "capture→decoded median %.1f ms over %d samples (p95 %.1f, MAD ±%.1f)",
                    median,
                    latencyMs.count,
                    latencyMs.p95 ?? 0,
                    latencyMs.medianAbsoluteDeviation ?? 0
                ))
            }
            let elapsed = Date().timeIntervalSince1970 - startedAt
            print(String(
                format: "keyframes %d in %.0f s (one per %.1f s), %d requested by the receiver",
                keyframesReceived,
                elapsed,
                keyframesReceived > 0 ? elapsed / Double(keyframesReceived) : 0,
                keyframeRequests
            ))
            print("NOTE: this is capture→decoded, not glass-to-glass. Add iPad touch/display")
            print("      and Mac present time; the camera method in specs/wireless.md is the")
            print("      number the go/kill call uses.")
            csv?.closeFile()
            exit(0)
        }
    }
}

let options = Options.parse(Array(CommandLine.arguments.dropFirst()))
let receiver = Receiver(options: options)

if options.headless {
    receiver.start()
    RunLoop.main.run()
} else {
    final class AppDelegate: NSObject, NSApplicationDelegate {
        let receiver: Receiver
        private var window: NSWindow?
        private var hud: NSTextField?

        init(receiver: Receiver) {
            self.receiver = receiver
            super.init()
        }

        func applicationDidFinishLaunching(_: Notification) {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1280, height: 800),
                styleMask: [.titled, .closable, .resizable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "SharePad wireless spike — receiver"
            window.center()

            let content = NSView(frame: window.contentLayoutRect)
            content.wantsLayer = true
            content.layer?.backgroundColor = NSColor.black.cgColor
            receiver.displayLayer.frame = content.bounds
            receiver.displayLayer.videoGravity = .resizeAspect
            receiver.displayLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
            content.layer?.addSublayer(receiver.displayLayer)

            let hud = NSTextField(labelWithString: "starting…")
            hud.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
            hud.textColor = .white
            hud.backgroundColor = NSColor.black.withAlphaComponent(0.55)
            hud.drawsBackground = true
            hud.maximumNumberOfLines = 6
            hud.frame = NSRect(x: 12, y: content.bounds.height - 96, width: 720, height: 84)
            hud.autoresizingMask = [.minYMargin, .maxXMargin]
            content.addSubview(hud)
            self.hud = hud

            window.contentView = content
            window.makeKeyAndOrderFront(nil)
            self.window = window

            receiver.onHUD = { [weak hud] text in
                hud?.stringValue = text
            }
            receiver.start()
        }

        func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
            true
        }

        func applicationWillTerminate(_: Notification) {
            receiver.finish()
        }
    }

    let application = NSApplication.shared
    let delegate = AppDelegate(receiver: receiver)
    application.delegate = delegate
    application.setActivationPolicy(.regular)
    application.activate(ignoringOtherApps: true)
    application.run()
}
