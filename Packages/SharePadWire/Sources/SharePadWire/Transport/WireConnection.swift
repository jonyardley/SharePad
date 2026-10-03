import Foundation
import Network
import os
import Security

public enum WireParameters {
    public static func stream() -> NWParameters {
        stream(security: .unauthenticated)
    }

    public static func stream(security: LinkSecurity) -> NWParameters {
        let options = NWProtocolTCP.Options()
        // Nagle would hold small frames back by tens of milliseconds.
        options.noDelay = true
        options.enableKeepalive = true
        options.keepaliveIdle = 2
        options.keepaliveInterval = 1
        options.keepaliveCount = 2

        let parameters = NWParameters(tls: security.tlsOptions(), tcp: options)
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
    public var onPairingMessage: (@Sendable (PairingMessage) -> Void)?

    private let connection: NWConnection
    private let queue: DispatchQueue
    private let log = Logger(subsystem: "co.sharepad.wire", category: "link")

    public init(connection: NWConnection, queue: DispatchQueue) {
        self.connection = connection
        self.queue = queue
    }

    public static func outbound(to endpoint: NWEndpoint, queue: DispatchQueue) -> WireConnection {
        outbound(to: endpoint, security: .unauthenticated, queue: queue)
    }

    public static func outbound(
        to endpoint: NWEndpoint,
        security: LinkSecurity,
        queue: DispatchQueue
    ) -> WireConnection {
        WireConnection(
            connection: NWConnection(
                to: endpoint,
                using: WireParameters.stream(security: security)
            ),
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

    public var interfaceSummary: String {
        guard let path = connection.currentPath else { return "no path" }
        let interfaces = path.availableInterfaces.map { "\($0.name) (\(Self.label(for: $0.type)))" }
        return interfaces.isEmpty ? "no interface" : interfaces.joined(separator: ", ")
    }

    private static func label(for type: NWInterface.InterfaceType) -> String {
        switch type {
        case .wifi: "wifi"
        case .wiredEthernet: "wired"
        case .cellular: "cellular"
        case .loopback: "loopback"
        case .other: "other"
        @unknown default: "unknown"
        }
    }

    public func send(_ message: WireMessage, whenSent: (@Sendable () -> Void)? = nil) {
        connection.send(content: message.encoded(), completion: .contentProcessed { _ in
            whenSent?()
        })
    }

    public func send(_ message: PairingMessage, whenSent: (@Sendable () -> Void)? = nil) {
        connection.send(content: message.encoded(), completion: .contentProcessed { _ in
            whenSent?()
        })
    }

    public func linkExporter() -> Data? {
        guard let metadata = tlsMetadata else { return nil }
        let label = LinkAuthentication.exporterLabel
        let secret = label.withCString { pointer in
            sec_protocol_metadata_create_secret(
                metadata,
                label.utf8.count,
                pointer,
                LinkAuthentication.exporterLength
            )
        }
        guard let secret else { return nil }
        let bytes = Data(secret as DispatchData)
        return bytes.count == LinkAuthentication.exporterLength ? bytes : nil
    }

    public var negotiatedTLS: (version: UInt16, suite: UInt16)? {
        Self.negotiatedTLS(of: connection)
    }

    static func negotiatedTLS(of connection: NWConnection) -> (version: UInt16, suite: UInt16)? {
        guard let metadata = tlsMetadata(of: connection) else { return nil }
        return (
            sec_protocol_metadata_get_negotiated_tls_protocol_version(metadata).rawValue,
            sec_protocol_metadata_get_negotiated_tls_ciphersuite(metadata).rawValue
        )
    }

    private var tlsMetadata: sec_protocol_metadata_t? {
        Self.tlsMetadata(of: connection)
    }

    private static func tlsMetadata(of connection: NWConnection) -> sec_protocol_metadata_t? {
        let metadata = connection.metadata(definition: NWProtocolTLS.definition) as? NWProtocolTLS
            .Metadata
        return metadata?.securityProtocolMetadata
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
        if PairingMessage.handles(typeCode) {
            do {
                try onPairingMessage?(PairingMessage.decode(typeCode: typeCode, payload: payload))
            } catch {
                log.error("undecodable pairing message \(typeCode): \(String(describing: error))")
                connection.cancel()
                return
            }
            readHeader()
            return
        }
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

    public convenience init(serviceName: String, queue: DispatchQueue) throws {
        try self.init(serviceName: serviceName, security: .unauthenticated, queue: queue)
    }

    public init(
        serviceName: String?,
        security: LinkSecurity,
        deviceID: UUID? = nil,
        queue: DispatchQueue
    ) throws {
        listener = try NWListener(using: WireParameters.stream(security: security))
        if let serviceName, let deviceID {
            listener.service = NWListener.Service(
                name: serviceName,
                type: WireService.type,
                txtRecord: WireService.txtRecord(deviceID: deviceID)
            )
        } else if let serviceName {
            listener.service = NWListener.Service(name: serviceName, type: WireService.type)
        }
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
    public var onLocalNetworkDenied: (@Sendable (Bool) -> Void)?

    private let browser: NWBrowser

    public init() {
        browser = NWBrowser(
            for: .bonjourWithTXTRecord(type: WireService.type, domain: nil),
            using: WireParameters.browse()
        )
    }

    public func start(queue: DispatchQueue) {
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            self?.onResults?(Array(results))
        }
        browser.stateUpdateHandler = { [weak self] state in
            self?.onLocalNetworkDenied?(Self.isLocalNetworkDenied(state))
        }
        browser.start(queue: queue)
    }

    public func cancel() {
        browser.cancel()
    }

    // A refused local network prompt surfaces as a DNS-SD policy error, not a
    // state of its own (Apple TN3179, "Understanding local network privacy").
    public static func isLocalNetworkDenied(_ state: NWBrowser.State) -> Bool {
        switch state {
        case let .waiting(error), let .failed(error):
            error == .dns(DNSServiceErrorType(kDNSServiceErr_PolicyDenied))
        default:
            false
        }
    }
}

public extension NWBrowser.Result {
    var serviceName: String {
        if case let .service(name, _, _, _) = endpoint {
            return name
        }
        return "\(endpoint)"
    }

    var deviceID: UUID? {
        guard case let .bonjour(record) = metadata else { return nil }
        return WireService.deviceID(in: record)
    }
}
