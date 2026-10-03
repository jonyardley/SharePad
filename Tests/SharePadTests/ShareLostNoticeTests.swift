@testable import SharePad
import XCTest

final class ShareLostNoticeTests: XCTestCase {
    func testACableLossAsksForTheCable() {
        let notice = ShareLostNotice(feed: .usb)
        XCTAssertEqual(notice.symbol, "cable.connector.slash")
        XCTAssertEqual(notice.message, "iPad disconnected. Reconnect it to carry on.")
    }

    func testAWirelessLossPointsAtTheIPadApp() {
        let notice = ShareLostNotice(feed: .wireless)
        XCTAssertEqual(notice.symbol, "wifi.slash")
        XCTAssertEqual(notice.message, "iPad lost over Wi-Fi. Open SharePad on it to carry on.")
    }
}
