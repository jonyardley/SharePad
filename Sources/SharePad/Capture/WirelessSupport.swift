import dnssd
import Network

enum LocalNetworkProbe {
    // No API reports the Local Network privilege (TN3179). Bonjour registration
    // is gated, so a denied listener waits with kDNSServiceErr_PolicyDenied.
    static func access(for state: NWListener.State) -> LocalNetworkAccess? {
        switch state {
        case let .waiting(error), let .failed(error):
            isPolicyDenied(error) ? .denied : nil
        default:
            nil
        }
    }

    static func isPolicyDenied(_ error: NWError) -> Bool {
        guard case let .dns(code) = error else { return false }
        return code == DNSServiceErrorType(kDNSServiceErr_PolicyDenied)
    }
}

// @unchecked Sendable: created and resolved only on the receiver's queue.
final class ResolveOnce: @unchecked Sendable {
    private var continuation: CheckedContinuation<Bool, Never>?

    init(_ continuation: CheckedContinuation<Bool, Never>) {
        self.continuation = continuation
    }

    func resolve(_ value: Bool) {
        continuation?.resume(returning: value)
        continuation = nil
    }
}
