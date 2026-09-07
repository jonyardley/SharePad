import Foundation
import Network

public enum SpikeParameters {
    public static func tcp() -> NWParameters {
        let options = NWProtocolTCP.Options()
        // Nagle would coalesce small frames and add tens of milliseconds to the
        // thing this spike exists to measure.
        options.noDelay = true
        options.enableKeepalive = true
        options.keepaliveIdle = 2

        let parameters = NWParameters(tls: nil, tcp: options)
        parameters.includePeerToPeer = true
        parameters.serviceClass = .interactiveVideo
        return parameters
    }

    public static func browse() -> NWParameters {
        let parameters = NWParameters()
        parameters.includePeerToPeer = true
        return parameters
    }
}

public final class SpikeConnection {
    public enum Event {
        case ready
        case waiting(Error)
        case failed(Error?)
        case cancelled
        case message(SpikeMessage)
    }

    /// Frames are dropped rather than queued once this much data is unacknowledged
    /// by the transport. Queuing behind a congested Wi-Fi link turns a latency
    /// problem into an unbounded one: better to lose a frame than to fall behind.
    public var backlogLimitBytes = 512 * 1024

    public var onEvent: ((Event) -> Void)?
    public private(set) var droppedFrames = 0
    public private(set) var sentBytes = 0

    private let connection: NWConnection
    private let queue: DispatchQueue
    private var inFlightBytes = 0

    public init(connection: NWConnection, queue: DispatchQueue) {
        self.connection = connection
        self.queue = queue
    }

    public static func outbound(to endpoint: NWEndpoint, queue: DispatchQueue) -> SpikeConnection {
        SpikeConnection(
            connection: NWConnection(to: endpoint, using: SpikeParameters.tcp()),
            queue: queue
        )
    }

    public func start() {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                onEvent?(.ready)
                readMessage()
            case let .waiting(error):
                onEvent?(.waiting(error))
            case let .failed(error):
                onEvent?(.failed(error))
            case .cancelled:
                onEvent?(.cancelled)
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    public func cancel() {
        connection.cancel()
    }

    public func send(_ message: SpikeMessage, droppable: Bool = false) {
        let data = message.encoded()
        if droppable, inFlightBytes + data.count > backlogLimitBytes {
            droppedFrames += 1
            return
        }
        inFlightBytes += data.count
        sentBytes += data.count
        connection.send(content: data, completion: .contentProcessed { [weak self] _ in
            self?.inFlightBytes -= data.count
        })
    }

    private func readMessage() {
        connection.receive(
            minimumIncompleteLength: SpikeService.headerLength,
            maximumLength: SpikeService.headerLength
        ) { [weak self] header, _, isComplete, error in
            guard let self else { return }
            if let error {
                onEvent?(.failed(error))
                return
            }
            guard let header, header.count == SpikeService.headerLength else {
                if isComplete { onEvent?(.failed(nil)) }
                return
            }

            let typeCode = header[header.startIndex]
            let length = header.dropFirst().reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
            readPayload(typeCode: typeCode, length: Int(length))
        }
    }

    private func readPayload(typeCode: UInt8, length: Int) {
        guard length > 0 else {
            deliver(typeCode: typeCode, payload: Data())
            return
        }
        connection.receive(minimumIncompleteLength: length, maximumLength: length) {
            [weak self] payload, _, isComplete, error in
            guard let self else { return }
            if let error {
                onEvent?(.failed(error))
                return
            }
            guard let payload, payload.count == length else {
                if isComplete { onEvent?(.failed(nil)) }
                return
            }
            deliver(typeCode: typeCode, payload: payload)
        }
    }

    private func deliver(typeCode: UInt8, payload: Data) {
        do {
            try onEvent?(.message(SpikeMessage.decode(typeCode: typeCode, payload: payload)))
        } catch {
            print("[link] undecodable message type \(typeCode): \(error)")
        }
        readMessage()
    }
}

public final class SpikeListener {
    public var onConnection: ((SpikeConnection) -> Void)?
    public var onStateChange: ((NWListener.State) -> Void)?

    private let listener: NWListener
    private let queue: DispatchQueue

    public init(serviceName: String, queue: DispatchQueue) throws {
        listener = try NWListener(using: SpikeParameters.tcp())
        listener.service = NWListener.Service(name: serviceName, type: SpikeService.type)
        self.queue = queue
    }

    public var port: UInt16? {
        listener.port?.rawValue
    }

    public func start() {
        listener.stateUpdateHandler = { [weak self] state in
            self?.onStateChange?(state)
        }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            onConnection?(SpikeConnection(connection: connection, queue: queue))
        }
        listener.start(queue: queue)
    }

    public func cancel() {
        listener.cancel()
    }
}

public final class SpikeBrowser {
    public var onResults: (([NWBrowser.Result]) -> Void)?

    private let browser: NWBrowser

    public init() {
        browser = NWBrowser(
            for: .bonjour(type: SpikeService.type, domain: nil),
            using: SpikeParameters.browse()
        )
    }

    public func start(queue: DispatchQueue) {
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            self?.onResults?(Array(results))
        }
        browser.start(queue: queue)
    }

    public func cancel() {
        browser.cancel()
    }
}

public extension NWBrowser.Result {
    var displayName: String {
        if case let .service(name, _, _, _) = endpoint {
            return name
        }
        return "\(endpoint)"
    }
}
