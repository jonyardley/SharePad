#if DEBUG
    import dnssd
    import Network
    @testable import SharePad
    import XCTest

    final class LocalNetworkProbeTests: XCTestCase {
        private let policyDenied = NWError.dns(DNSServiceErrorType(kDNSServiceErr_PolicyDenied))

        func testWaitingOnPolicyDeniedIsDenied() {
            XCTAssertEqual(LocalNetworkProbe.access(for: .waiting(policyDenied)), .denied)
        }

        func testFailedOnPolicyDeniedIsDenied() {
            XCTAssertEqual(LocalNetworkProbe.access(for: .failed(policyDenied)), .denied)
        }

        func testOtherErrorsSayNothingAboutAccess() {
            let refused = NWError.posix(.ECONNREFUSED)
            XCTAssertNil(LocalNetworkProbe.access(for: .waiting(refused)))
            let otherDNS = NWError.dns(DNSServiceErrorType(kDNSServiceErr_NoSuchRecord))
            XCTAssertNil(LocalNetworkProbe.access(for: .failed(otherDNS)))
        }

        func testReadyIsLeftToTheReceiver() {
            XCTAssertNil(LocalNetworkProbe.access(for: .ready))
        }
    }
#endif
