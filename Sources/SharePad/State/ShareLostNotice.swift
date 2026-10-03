struct ShareLostNotice: Equatable {
    let symbol: String
    let message: String

    init(feed: FeedKind) {
        switch feed {
        case .usb:
            symbol = "cable.connector.slash"
            message = "iPad disconnected. Reconnect it to carry on."
        case .wireless:
            symbol = "wifi.slash"
            message = "iPad lost over Wi-Fi. Open SharePad on it to carry on."
        }
    }
}
