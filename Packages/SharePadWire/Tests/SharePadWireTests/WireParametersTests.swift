import SharePadWire
import XCTest

final class WireParametersTests: XCTestCase {
    func testStreamExcludesPeerToPeer() {
        XCTAssertFalse(WireParameters.stream().includePeerToPeer)
    }

    func testBrowseExcludesPeerToPeer() {
        XCTAssertFalse(WireParameters.browse().includePeerToPeer)
    }
}
