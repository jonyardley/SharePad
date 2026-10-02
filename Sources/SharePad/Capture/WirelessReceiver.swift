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
        let thumbnailDisplayLayer: AVSampleBufferDisplayLayer
        let croppedDisplay: CroppedVideoLayer
        let croppedThumbnail: CroppedVideoLayer
        let videoSizes: AsyncStream<CGSize>
        let statuses: AsyncStream<WirelessStatus>

        var hostedLayer: CALayer {
            croppedDisplay
        }

        var thumbnailLayer: CALayer {
            croppedThumbnail
        }

        private static let minThumbnailInterval = 1.0 / 15.0
        private static let listenerRetryDelay: TimeInterval = 2

        let queue = DispatchQueue(label: "com.jonyardley.sharepad.wireless")
        let log = Logger(subsystem: "com.jonyardley.sharepad", category: "wireless")
        let decoder = H264Decoder()
        private let displayRenderer: AVSampleBufferVideoRenderer
        private let thumbnailRenderer: AVSampleBufferVideoRenderer
        private let deviceName: String
        private let store: PairingStore
        private let sizeContinuation: AsyncStream<CGSize>.Continuation
        private let statusContinuation: AsyncStream<WirelessStatus>.Continuation

        var identity: Hello?
        private var listener: WireListener?
        private var plan: ListenerPlan?
        var connections: [ConnectionID: WireConnection] = [:]
        var gates: [ConnectionID: LinkGate] = [:]
        private var nextConnectionID = 0
        var link = ReceiverLink()
        var window = PairingWindow()
        var book = PairingBook()
        var health = PairingHealth()
        private var allowWireless = true
        private var hasLoaded = false
        var keyframes = KeyframeRequester()
        var status = WirelessStatus()
        private var lastSize: CGSize?
        private var lastCrop: FeedCrop?
        private var thumbnailActive = false
        private var lastThumbnailAt: Double?
        private var frameWaiter: (@Sendable (Bool) -> Void)?
        private var frameWaiterID = 0
        private var isStopped = false
        private var framesShown = 0

        @MainActor
        init(
            deviceName: String = SCDynamicStoreCopyComputerName(nil, nil) as String? ?? "Mac",
            store: PairingStore = KeychainPairingStore()
        ) {
            self.deviceName = deviceName
            self.store = store
            displayLayer = AVSampleBufferDisplayLayer()
            thumbnailDisplayLayer = AVSampleBufferDisplayLayer()
            croppedDisplay = CroppedVideoLayer(video: displayLayer)
            croppedThumbnail = CroppedVideoLayer(video: thumbnailDisplayLayer)
            displayRenderer = displayLayer.sampleBufferRenderer
            thumbnailRenderer = thumbnailDisplayLayer.sampleBufferRenderer
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
                loadPairings()
                applyPlan()
                logDisplayHealth()
            }
        }

        func stop() async {
            await withCheckedContinuation { continuation in
                queue.async { [self] in
                    isStopped = true
                    listener?.cancel()
                    listener = nil
                    plan = nil
                    connections.values.forEach { $0.cancel() }
                    connections.removeAll()
                    gates.removeAll()
                    link = ReceiverLink()
                    var cleared = WirelessStatus(localNetwork: status.localNetwork)
                    cleared.paired = status.paired
                    status = cleared
                    publish(status)
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

        func setAllowWireless(_ allowed: Bool) {
            queue.async { [self] in
                guard allowed != allowWireless else { return }
                allowWireless = allowed
                if !allowed {
                    for id in pairedConnections(peerID: nil) {
                        close(id)
                    }
                }
                applyPlan()
            }
        }

        func openPairing() {
            queue.async { [self] in
                let offer = PairingOffer.generate(at: Self.wallClock)
                applyWindow(window.reduce(.open(offer)))
                queue.asyncAfter(deadline: .now() + PairingOffer.lifetime) { [self] in
                    applyWindow(window.reduce(.tick(at: Self.wallClock)))
                }
            }
        }

        func closePairing() {
            queue.async { [self] in
                applyWindow(window.reduce(.close))
            }
        }

        func forget(iPad id: UUID) {
            queue.async { [self] in
                _ = health.reduce(.handshakeSucceeded(id))
                applyBook(book.reduce(.forget(peerID: id)))
            }
        }

        static var uptime: TimeInterval {
            ProcessInfo.processInfo.systemUptime
        }

        static var wallClock: TimeInterval {
            Date().timeIntervalSince1970
        }

        // ── Pairings and the listener ──

        private func loadPairings() {
            guard !hasLoaded else { return }
            hasLoaded = true
            do {
                identity = try Hello(deviceID: store.localDeviceID(), deviceName: deviceName)
                _ = try book.reduce(.loaded(store.loadPairings()))
            } catch {
                log.error("pairing store unreadable: \(String(describing: error))")
                status.pairingStoreFailed = true
            }
            publishPairings()
        }

        // Network.framework fixes a listener's keys when it is made, so a changed plan
        // replaces the listener; connections it already accepted carry on.
        func applyPlan() {
            let next = ListenerPlan.make(
                offering: window.acceptingCode,
                paired: book.records,
                allowWireless: allowWireless
            )
            guard next != plan || (next != nil && listener == nil) else { return }
            plan = next
            listener?.cancel()
            listener = nil
            openListener()
        }

        private func openListener() {
            guard !isStopped, let plan, let identity else { return }
            do {
                let listener = try WireListener(
                    serviceName: identity.deviceName,
                    security: plan.security,
                    deviceID: identity.deviceID,
                    queue: queue
                )
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

        func publishPairings() {
            status.paired = book.records
                .sorted { $0.pairedAt < $1.pairedAt }
                .map { PairedIPad($0, needsPairing: health.isBroken($0.peerID)) }
            status.pairing = PairingProgress(window.phase)
            publish(status)
        }

        func accept(_ connection: WireConnection) {
            nextConnectionID += 1
            let id = nextConnectionID
            connections[id] = connection
            gates[id] = LinkGate()
            connection.onEvent = { [weak self] event in
                self?.handle(event, from: id)
            }
            connection.onPairingMessage = { [weak self] message in
                self?.handle(message, from: id)
            }
            connection.start()
        }
    }

    // ── Connections: the gate, pairing and the link rules ──

    extension WirelessReceiver {
        private func handle(_ event: WireConnection.Event, from id: ConnectionID) {
            switch event {
            case .ready:
                apply(link.reduce(.opened(id)))
            case let .message(.hello(hello)):
                helloReceived(hello, from: id)
            case let .message(message):
                guard admit(.streamMessage, from: id) else { return }
                handle(message, from: id)
            case .failed, .cancelled:
                guard connections.removeValue(forKey: id) != nil else { return }
                gates[id] = nil
                apply(link.reduce(.closed(id, at: Self.uptime)))
                applyWindow(window.reduce(.connectionClosed(id)))
            case .waiting:
                break
            }
        }

        private func handle(_ message: PairingMessage, from id: ConnectionID) {
            switch message {
            case let .authenticate(credential):
                authenticate(credential, from: id)
            case let .stored(pairingID):
                guard admit(.pairingMessage, from: id) else { return }
                applyWindow(window.reduce(.stored(id, pairingID: pairingID, at: Self.wallClock)))
            case let .forgotten(pairingID):
                guard case let .open(.paired(record), _) = gates[id]?.phase,
                      admit(.forgetNotice, from: id) else { return }
                if record.pairingID == pairingID {
                    applyHealth(health.reduce(.peerForgot(record.peerID)))
                }
                close(id)
            case .grant:
                close(id)
            }
        }

        private func authenticate(_ credential: LinkCredential, from id: ConnectionID) {
            let paired = plan?.paired ?? []
            let peer = LinkAuthentication.verify(
                credential,
                exporter: connections[id]?.linkExporter(),
                pairingCode: window.acceptingCode,
                paired: paired
            )
            if peer == nil, case let .paired(pairingID, _) = credential,
               let record = paired.first(where: { $0.pairingID == pairingID }) {
                applyHealth(health.reduce(.handshakeFailed(record.peerID)))
            }
            admit(.credentialChecked(peer), from: id)
        }

        private func helloReceived(_ hello: Hello, from id: ConnectionID) {
            guard var gate = gates[id] else { return }
            let decision = gate.reduce(.helloReceived(hello))
            gates[id] = gate
            switch decision {
            case let .admitHello(.paired(record), hello):
                applyHealth(health.reduce(.handshakeSucceeded(record.peerID)))
                applyBook(book.reduce(.connected(peerID: record.peerID, at: Self.wallClock)))
                apply(link.reduce(.helloReceived(id, hello)))
            case let .admitHello(.pairing, hello):
                applyWindow(window.reduce(.pairingHello(id, hello, at: Self.wallClock)))
            case .pass:
                apply(link.reduce(.helloReceived(id, hello)))
            case .wait:
                break
            case let .close(reason):
                log.notice("gate closed \(id): \(String(describing: reason), privacy: .public)")
                close(id)
            }
        }

        @discardableResult
        private func admit(_ event: LinkGate.Event, from id: ConnectionID) -> Bool {
            guard var gate = gates[id] else { return false }
            let decision = gate.reduce(event)
            gates[id] = gate
            switch decision {
            case .pass, .admitHello:
                return true
            case .wait:
                return false
            case let .close(reason):
                log.notice("gate closed \(id): \(String(describing: reason), privacy: .public)")
                close(id)
                return false
            }
        }

        func close(_ id: ConnectionID) {
            connections[id]?.cancel()
        }

        func pairedConnections(peerID: UUID?) -> [ConnectionID] {
            gates.compactMap { id, gate in
                guard case let .open(.paired(record), _) = gate.phase,
                      peerID == nil || record.peerID == peerID else { return nil }
                return id
            }
        }

        private func applyWindow(_ effects: [PairingWindow.Effect]) {
            for effect in effects {
                switch effect {
                case .acceptPairing, .stopAcceptingPairing:
                    applyPlan()
                case let .sendGrant(id, grant):
                    connections[id]?.send(.grant(grant))
                case let .store(record):
                    _ = health.reduce(.handshakeSucceeded(record.peerID))
                    applyBook(book.reduce(.paired(record)))
                case let .close(id, _):
                    close(id)
                }
            }
            publishPairings()
        }

        func applyBook(_ effects: [PairingBook.Effect]) {
            for effect in effects {
                switch effect {
                case let .save(record):
                    persist { try store.savePairing(record) }
                case let .delete(peerID):
                    persist { try store.deletePairing(peerID: peerID) }
                case let .dropConnections(peerID):
                    pairedConnections(peerID: peerID).forEach(close)
                case .reloadCredentials:
                    applyPlan()
                }
            }
            publishPairings()
        }

        private func persist(_ write: () throws -> Void) {
            do {
                try write()
                status.pairingStoreFailed = false
            } catch {
                log.error("pairing store write failed: \(String(describing: error))")
                status.pairingStoreFailed = true
            }
        }

        private func applyHealth(_ effects: [PairingHealth.Effect]) {
            guard !effects.isEmpty else { return }
            publishPairings()
        }

        private func apply(_ effects: [ReceiverLink.Effect]) {
            for effect in effects {
                log.notice("link: \(String(describing: effect), privacy: .public)")
                switch effect {
                case let .sendHello(id):
                    if let identity { connections[id]?.send(.hello(identity)) }
                case let .close(id, _):
                    close(id)
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
            guard case let .live(current) = link.phase, current.connection == id else { return }
            switch message {
            case let .config(config):
                decoder.configure(parameterSets: config.parameterSets)
                applyCrop(FeedCrop(
                    width: config.width,
                    height: config.height,
                    canvas: config.canvas
                ))
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

        func requestKeyframe(after event: KeyframeRequester.Event) {
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
        private func applyCrop(_ crop: FeedCrop?) {
            guard let crop, crop != lastCrop else { return }
            lastCrop = crop
            log.notice("""
            crop video=\(Int(crop.video.width))x\(Int(crop.video.height)) \
            canvas=\(String(describing: crop.canvas), privacy: .public)
            """)
            let layers = [croppedDisplay, croppedThumbnail]
            DispatchQueue.main.async {
                for layer in layers {
                    layer.crop = crop
                }
            }
            if crop.visibleSize != lastSize {
                lastSize = crop.visibleSize
                sizeContinuation.yield(crop.visibleSize)
            }
        }

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
