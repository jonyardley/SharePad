import Network
import SharePadWire
import XCTest

final class WireParametersTests: XCTestCase {
    func testStreamKeepsPeerToPeerOn() {
        XCTAssertTrue(WireParameters.stream().includePeerToPeer)
    }

    func testBrowseKeepsPeerToPeerOn() {
        XCTAssertTrue(WireParameters.browse().includePeerToPeer)
    }

    func testPolicyDeniedBrowseReadsAsLocalNetworkDenied() {
        let denied = NWError.dns(DNSServiceErrorType(kDNSServiceErr_PolicyDenied))
        XCTAssertTrue(WireBrowser.isLocalNetworkDenied(.waiting(denied)))
        XCTAssertTrue(WireBrowser.isLocalNetworkDenied(.failed(denied)))
    }

    func testOtherBrowseStatesAreNotDenial() {
        XCTAssertFalse(WireBrowser.isLocalNetworkDenied(.ready))
        XCTAssertFalse(WireBrowser.isLocalNetworkDenied(.waiting(.posix(.ENETDOWN))))
    }
}
