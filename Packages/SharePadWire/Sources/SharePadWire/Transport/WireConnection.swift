import Foundation
import Network
import os

public enum WireParameters {
    public static func stream() -> NWParameters {
        let options = NWProtocolTCP.Options()
        // Nagle would hold small frames back by tens of milliseconds.
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

// @unchecked: handlers are set before `start`; from then on everything runs on the
// queue it was started on, which is also where Network.framework calls back.
public final class WireConnection: @unchecked Sendable {
    public enum Event: Sendable {
        case ready
        case waiting(NWError)
        case failed(NWError?)
        case cancelled
        case message(WireMessage)
    }

    public var onEvent: (@Sendable (Event) -> Void)?

    private let connection: NWConnection
    private let queue: DispatchQueue
    private let log = Logger(subsystem: "co.sharepad.wire", category: "link")

    public init(connection: NWConnection, queue: DispatchQueue) {
        self.connection = connection
        self.queue = queue
    }

    public static func outbound(to endpoint: NWEndpoint, queue: DispatchQueue) -> WireConnection {
        WireConnection(
            connection: NWConnection(to: endpoint, using: WireParameters.stream()),
            queue: queue
        )
    }

    public func start() {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                onEvent?(.ready)
                readHeader()
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

    public func send(_ message: WireMessage, whenSent: (@Sendable () -> Void)? = nil) {
        connection.send(content: message.encoded(), completion: .contentProcessed { _ in
            whenSent?()
        })
    }

    private func readHeader() {
        connection.receive(
            minimumIncompleteLength: WireService.headerLength,
            maximumLength: WireService.headerLength
        ) { [weak self] header, _, isComplete, error in
            guard let self else { return }
            if let error {
                onEvent?(.failed(error))
                return
            }
            guard let header, header.count == WireService.headerLength else {
                if isComplete { onEvent?(.failed(nil)) }
                return
            }
            do {
                let (typeCode, length) = try WireMessage.header(header)
                readPayload(typeCode: typeCode, length: length)
            } catch {
                log.error("bad header: \(String(describing: error))")
                connection.cancel()
            }
        }
    }

    private func readPayload(typeCode: UInt8, length: Int) {
        guard length > 0 else {
            deliver(typeCode: typeCode, payload: Data())
            return
        }
        connection.receive(
            minimumIncompleteLength: length,
            maximumLength: length
        ) { [weak self] payload, _, isComplete, error in
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
            try onEvent?(.message(WireMessage.decode(typeCode: typeCode, payload: payload)))
        } catch {
            log.error("undecodable message \(typeCode): \(String(describing: error))")
        }
        readHeader()
    }
}

// @unchecked: handlers are set before `start`; from then on everything runs on the
// queue it was started on, which is also where Network.framework calls back.
public final class WireListener: @unchecked Sendable {
    public var onConnection: (@Sendable (WireConnection) -> Void)?
    public var onStateChange: (@Sendable (NWListener.State) -> Void)?

    private let listener: NWListener
    private let queue: DispatchQueue

    public init(serviceName: String, queue: DispatchQueue) throws {
        listener = try NWListener(using: WireParameters.stream())
        listener.service = NWListener.Service(name: serviceName, type: WireService.type)
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
            onConnection?(WireConnection(connection: connection, queue: queue))
        }
        listener.start(queue: queue)
    }

    public func cancel() {
        listener.cancel()
    }
}

// @unchecked: handlers are set before `start`; from then on everything runs on the
// queue it was started on, which is also where Network.framework calls back.
public final class WireBrowser: @unchecked Sendable {
    public var onResults: (@Sendable ([NWBrowser.Result]) -> Void)?

    private let browser: NWBrowser

    public init() {
        browser = NWBrowser(
            for: .bonjour(type: WireService.type, domain: nil),
            using: WireParameters.browse()
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
    var serviceName: String {
        if case let .service(name, _, _, _) = endpoint {
            return name
        }
        return "\(endpoint)"
    }
}
