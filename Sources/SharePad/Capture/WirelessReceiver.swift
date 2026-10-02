#if DEBUG
    import AVFoundation
    import Network
    import os
    import SharePadWire
    import SystemConfiguration

    // @unchecked Sendable: every mutable property is touched only on `queue`; the
    // layers are created on main and fed off-main only through their renderers.
    final class WirelessReceiver: WirelessFeeding, @unchecked Sendable {
        let displayLayer: AVSampleBufferDisplayLayer
        let thumbnailLayer: AVSampleBufferDisplayLayer
        let videoSizes: AsyncStream<CGSize>
        let statuses: AsyncStream<WirelessStatus>

        var hostedLayer: CALayer {
            displayLayer
        }

        private static let minThumbnailInterval = 1.0 / 15.0
        private static let listenerRetryDelay: TimeInterval = 2

        private let queue = DispatchQueue(label: "com.jonyardley.sharepad.wireless")
        private let log = Logger(subsystem: "com.jonyardley.sharepad", category: "wireless")
        private let decoder = H264Decoder()
        private let displayRenderer: AVSampleBufferVideoRenderer
        private let thumbnailRenderer: AVSampleBufferVideoRenderer
        private let identity: Hello
        private let sizeContinuation: AsyncStream<CGSize>.Continuation
        private let statusContinuation: AsyncStream<WirelessStatus>.Continuation

        private var listener: WireListener?
        private var connections: [ConnectionID: WireConnection] = [:]
        private var nextConnectionID = 0
        private var link = ReceiverLink()
        private var keyframes = KeyframeRequester()
        private var status = WirelessStatus()
        private var lastSize: CGSize?
        private var thumbnailActive = false
        private var lastThumbnailAt: Double?
        private var frameWaiter: (@Sendable (Bool) -> Void)?
        private var frameWaiterID = 0
        private var isStopped = false
        private var framesShown = 0

        @MainActor
        init(deviceName: String = SCDynamicStoreCopyComputerName(nil, nil) as String? ?? "Mac") {
            identity = Hello(deviceID: UUID(), deviceName: deviceName)
            displayLayer = AVSampleBufferDisplayLayer()
            displayLayer.videoGravity = .resizeAspect
            thumbnailLayer = AVSampleBufferDisplayLayer()
            thumbnailLayer.videoGravity = .resizeAspect
            displayRenderer = displayLayer.sampleBufferRenderer
            thumbnailRenderer = thumbnailLayer.sampleBufferRenderer
            (videoSizes, sizeContinuation) = AsyncStream.makeStream(of: CGSize.self)
            (statuses, statusContinuation) = AsyncStream.makeStream(of: WirelessStatus.self)
            decoder.onDecodedFrame = { [weak self] frame in
                guard let self else { return }
                queue.async { [weak self] in self?.show(frame.pixelBuffer) }
            }
            decoder.onDecodeFailed = { [weak self] _ in
                guard let self else { return }
                queue.async { [weak self] in
                    self?.requestKeyframe(after: .decodeFailed(at: Self.uptime))
                }
            }
        }

        func start() {
            queue.async { [self] in
                isStopped = false
                openListener()
                logDisplayHealth()
            }
        }

        func stop() async {
            await withCheckedContinuation { continuation in
                queue.async { [self] in
                    isStopped = true
                    listener?.cancel()
                    listener = nil
                    connections.values.forEach { $0.cancel() }
                    connections.removeAll()
                    link = ReceiverLink()
                    publish(WirelessStatus(localNetwork: status.localNetwork))
                    continuation.resume()
                }
            }
        }

        func setThumbnailActive(_ active: Bool) {
            queue.async { [self] in
                thumbnailActive = active
                if !active {
                    lastThumbnailAt = nil
                    thumbnailRenderer.flush()
                }
            }
        }

        func awaitFrame(timeout: TimeInterval) async -> Bool {
            await withCheckedContinuation { continuation in
                queue.async { [self] in
                    let once = ResolveOnce(continuation)
                    frameWaiterID += 1
                    let id = frameWaiterID
                    frameWaiter = { once.resolve($0) }
                    queue.asyncAfter(deadline: .now() + timeout) { [self] in
                        if frameWaiterID == id { frameWaiter = nil }
                        once.resolve(false)
                    }
                }
            }
        }

        private static var uptime: TimeInterval {
            ProcessInfo.processInfo.systemUptime
        }

        // ── Listener ──

        private func openListener() {
            do {
                let listener = try WireListener(serviceName: identity.deviceName, queue: queue)
                listener.onStateChange = { [weak self] state in
                    self?.listenerChanged(state)
                }
                listener.onConnection = { [weak self] connection in
                    self?.accept(connection)
                }
                listener.start()
                self.listener = listener
            } catch {
                log.error("listener not created: \(String(describing: error))")
                status.listenerFailed = true
                publish(status)
                retryListener()
            }
        }

        private func listenerChanged(_ state: NWListener.State) {
            if let access = LocalNetworkProbe.access(for: state) {
                status.localNetwork = access
                publish(status)
            } else if case .ready = state {
                status.localNetwork = .granted
                status.listenerFailed = false
                publish(status)
            }
            if case let .failed(error) = state {
                log.error("listener failed: \(String(describing: error))")
                status.listenerFailed = true
                publish(status)
                listener?.cancel()
                listener = nil
                retryListener()
            }
        }

        // A failed NWListener can't be restarted, only replaced.
        private func retryListener() {
            queue.asyncAfter(deadline: .now() + Self.listenerRetryDelay) { [self] in
                guard !isStopped, listener == nil else { return }
                openListener()
            }
        }
    }

    // ── Connections and the link rules ──

    extension WirelessReceiver {
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
            case .failed, .cancelled:
                guard connections.removeValue(forKey: id) != nil else { return }
                apply(link.reduce(.closed(id, at: Self.uptime)))
            case .waiting:
                break
            }
        }

        private func apply(_ effects: [ReceiverLink.Effect]) {
            for effect in effects {
                log.notice("link: \(String(describing: effect), privacy: .public)")
                switch effect {
                case let .sendHello(id):
                    connections[id]?.send(.hello(identity))
                case let .close(id, _):
                    connections.removeValue(forKey: id)?.cancel()
                case .adopt:
                    adopted()
                case let .sendPause(id):
                    connections[id]?.send(.pause)
                case let .sendResume(id):
                    connections[id]?.send(.resume)
                case let .scheduleHoldCheck(after):
                    status.isReconnecting = true
                    publish(status)
                    queue.asyncAfter(deadline: .now() + after) { [self] in
                        apply(link.reduce(.holdElapsed(at: Self.uptime)))
                    }
                case .endShare:
                    status.peer = nil
                    status.isReceiving = false
                    status.isReconnecting = false
                    lastSize = nil
                    publish(status)
                }
            }
        }

        private func adopted() {
            guard case let .live(current) = link.phase else { return }
            let peer = WirelessPeer(id: current.hello.deviceID, name: current.hello.deviceName)
            if status.peer != peer {
                status.isReceiving = false
            }
            status.peer = peer
            status.isReconnecting = false
            publish(status)
            requestKeyframe(after: .connected(at: Self.uptime))
        }

        private var activeConnection: WireConnection? {
            guard case let .live(current) = link.phase else { return nil }
            return connections[current.connection]
        }

        private func handle(_ message: WireMessage, from id: ConnectionID) {
            if case let .hello(hello) = message {
                apply(link.reduce(.helloReceived(id, hello)))
                return
            }
            guard case let .live(current) = link.phase, current.connection == id else { return }
            switch message {
            case let .config(config):
                decoder.configure(parameterSets: config.parameterSets)
                let size = CGSize(width: Int(config.width), height: Int(config.height))
                if size.width > 0, size.height > 0, size != lastSize {
                    lastSize = size
                    sizeContinuation.yield(size)
                }
            case let .frame(frame):
                let effects = keyframes.reduce(
                    .frameArrived(isKeyframe: frame.isKeyframe, at: Self.uptime)
                )
                guard sendRequests(effects), decoder.isConfigured else { return }
                decoder.decode(frame: frame)
            case .hello, .ping, .pong, .requestKeyframe, .pause, .resume:
                break
            }
        }

        private func requestKeyframe(after event: KeyframeRequester.Event) {
            sendRequests(keyframes.reduce(event))
        }

        @discardableResult
        private func sendRequests(_ effects: [KeyframeRequester.Effect]) -> Bool {
            var shouldDecode = false
            for effect in effects {
                switch effect {
                case .sendRequest: activeConnection?.send(.requestKeyframe)
                case .decode: shouldDecode = true
                case .discard: break
                }
            }
            return shouldDecode
        }
    }

    // ── Decoded frames ──

    extension WirelessReceiver {
        private func show(_ pixelBuffer: CVPixelBuffer) {
            guard status.peer != nil, let sample = Self.immediateSample(pixelBuffer) else { return }
            let renderer = displayRenderer
            if renderer.status == .failed {
                renderer.flush()
                requestKeyframe(after: .layerFlushed(at: Self.uptime))
            }
            renderer.enqueue(sample)
            framesShown += 1
            renderThumbnail(sample)
            if let frameWaiter {
                self.frameWaiter = nil
                frameWaiter(true)
            }
            if !status.isReceiving {
                status.isReceiving = true
                publish(status)
            }
        }

        private func renderThumbnail(_ sample: CMSampleBuffer) {
            let now = Self.uptime
            let renderer = thumbnailRenderer
            guard thumbnailActive,
                  shouldRenderFrame(currentSeconds: now,
                                    lastRenderedSeconds: lastThumbnailAt,
                                    minInterval: Self.minThumbnailInterval),
                  renderer.isReadyForMoreMediaData
            else { return }
            renderer.enqueue(sample)
            lastThumbnailAt = now
        }

        private func publish(_ status: WirelessStatus) {
            log.notice("""
            status peer=\(status.peer != nil) receiving=\(status.isReceiving) \
            reconnecting=\(status.isReconnecting) \
            localNetwork=\(String(describing: status.localNetwork), privacy: .public)
            """)
            statusContinuation.yield(status)
        }

        // Every 5 s while a peer is live: whether frames reach the share window's
        // renderer and whether it is taking them (W1 hardware check).
        private func logDisplayHealth() {
            queue.asyncAfter(deadline: .now() + 5) { [weak self] in
                guard let self, !isStopped else { return }
                if status.peer != nil {
                    let renderer = displayRenderer
                    let shown = framesShown
                    let state = renderer.status.rawValue
                    let ready = renderer.isReadyForMoreMediaData
                    let error = String(describing: renderer.error)
                    log.notice("""
                    display: frames=\(shown) status=\(state) ready=\(ready) \
                    error=\(error, privacy: .public)
                    """)
                    framesShown = 0
                }
                logDisplayHealth()
            }
        }

        // Decoded frames carry no timeline, so they are marked for immediate display;
        // any presentation-time scheduling would only add latency.
        private static func immediateSample(_ pixelBuffer: CVPixelBuffer) -> CMSampleBuffer? {
            var format: CMVideoFormatDescription?
            guard CMVideoFormatDescriptionCreateForImageBuffer(
                allocator: kCFAllocatorDefault,
                imageBuffer: pixelBuffer,
                formatDescriptionOut: &format
            ) == noErr, let format else { return nil }

            var timing = CMSampleTimingInfo(
                duration: .invalid,
                presentationTimeStamp: .invalid,
                decodeTimeStamp: .invalid
            )
            var sample: CMSampleBuffer?
            guard CMSampleBufferCreateReadyWithImageBuffer(
                allocator: kCFAllocatorDefault,
                imageBuffer: pixelBuffer,
                formatDescription: format,
                sampleTiming: &timing,
                sampleBufferOut: &sample
            ) == noErr, let sample else { return nil }

            if let attachments = CMSampleBufferGetSampleAttachmentsArray(
                sample,
                createIfNecessary: true
            ), CFArrayGetCount(attachments) > 0 {
                // The attachments array holds CFMutableDictionary values by CoreMedia's contract.
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
            return sample
        }
    }

#endif
