import AVFoundation

// One owner per source (specs/wireless-product.md §5): only the conformer touches
// its pipeline; AppModel hosts its layers and reads its sizes.
protocol FeedSource: AnyObject, Sendable {
    var hostedLayer: CALayer { get }
    var thumbnailLayer: CALayer { get }
    var videoSizes: AsyncStream<CGSize> { get }
    func stop() async
    func setThumbnailActive(_ active: Bool)
    func awaitFrame(timeout: TimeInterval) async -> Bool
}

protocol WirelessFeeding: FeedSource {
    var statuses: AsyncStream<WirelessStatus> { get }
    func start()
}
