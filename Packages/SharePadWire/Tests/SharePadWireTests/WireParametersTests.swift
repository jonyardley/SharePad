import SharePadWire
import XCTest

final class WireParametersTests: XCTestCase {
    func testStreamKeepsPeerToPeerOn() {
        XCTAssertTrue(WireParameters.stream().includePeerToPeer)
    }

    func testBrowseKeepsPeerToPeerOn() {
        XCTAssertTrue(WireParameters.browse().includePeerToPeer)
    }
}
