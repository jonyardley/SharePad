import AVFoundation
import SharePadWire

struct FeedCrop: Equatable, Sendable {
    let video: CGSize
    let canvas: CGRect

    init?(width: Int32, height: Int32, canvas rect: CanvasRect) {
        guard width > 0, height > 0 else { return nil }
        let video = CGSize(width: Int(width), height: Int(height))
        let canvas = CGRect(
            x: Int(rect.x),
            y: Int(rect.y),
            width: Int(rect.width),
            height: Int(rect.height)
        ).intersection(CGRect(origin: .zero, size: video))
        guard !canvas.isNull, canvas.width > 0, canvas.height > 0 else { return nil }
        self.video = video
        self.canvas = canvas
    }

    var visibleSize: CGSize {
        canvas.size
    }

    func shownRect(in bounds: CGRect) -> CGRect {
        let scale = min(bounds.width / canvas.width, bounds.height / canvas.height)
        let width = canvas.width * scale
        let height = canvas.height * scale
        return CGRect(
            x: bounds.midX - width / 2,
            y: bounds.midY - height / 2,
            width: width,
            height: height
        )
    }

    // `canvas` counts rows from the top of the frame; `yUp` says whether the layer
    // that receives the result counts its own y from the bottom.
    func videoFrame(in bounds: CGRect, yUp: Bool) -> CGRect {
        let shown = shownRect(in: bounds)
        let scale = shown.width / canvas.width
        let rowsHidden = yUp ? video.height - canvas.maxY : canvas.minY
        return CGRect(
            x: shown.minX - canvas.minX * scale,
            y: shown.minY - rowsHidden * scale,
            width: video.width * scale,
            height: video.height * scale
        )
    }
}

struct CropTracker {
    struct Change: Equatable {
        let crop: FeedCrop
        let size: CGSize?
    }

    private var applied: FeedCrop?
    private var reportedSize: CGSize?

    mutating func receive(_ crop: FeedCrop) -> Change? {
        guard crop != applied else { return nil }
        applied = crop
        guard crop.visibleSize != reportedSize else { return Change(crop: crop, size: nil) }
        reportedSize = crop.visibleSize
        return Change(crop: crop, size: crop.visibleSize)
    }

    mutating func shareEnded() {
        applied = nil
        reportedSize = nil
    }
}

// Shows only the sender's canvas rectangle of a decoded feed, so app chrome on the
// iPad never reaches the call (specs/wireless-product.md §4).
final class CroppedVideoLayer: CALayer, @unchecked Sendable {
    let video: AVSampleBufferDisplayLayer
    private let canvasMask = CALayer()

    var crop: FeedCrop? {
        didSet { layoutVideo() }
    }

    init(video: AVSampleBufferDisplayLayer) {
        self.video = video
        super.init()
        masksToBounds = true
        canvasMask.backgroundColor = CGColor(gray: 0, alpha: 1)
        video.videoGravity = .resizeAspect
        addSublayer(video)
    }

    override init(layer: Any) {
        let other = layer as? CroppedVideoLayer
        video = other?.video ?? AVSampleBufferDisplayLayer()
        crop = other?.crop
        super.init(layer: layer)
    }

    required init?(coder _: NSCoder) {
        nil
    }

    override var bounds: CGRect {
        didSet { layoutVideo() }
    }

    override func layoutSublayers() {
        super.layoutSublayers()
        layoutVideo()
    }

    private func layoutVideo() {
        guard video.superlayer === self else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let crop {
            video.videoGravity = .resize
            video.frame = crop.videoFrame(in: bounds, yUp: !Self.isFlipped(self))
            canvasMask.frame = crop.shownRect(in: bounds)
            mask = canvasMask
        } else {
            video.videoGravity = .resizeAspect
            video.frame = bounds
            mask = nil
        }
        CATransaction.commit()
    }

    static func isFlipped(_ layer: CALayer) -> Bool {
        var flipped = false
        var current: CALayer? = layer
        while let next = current {
            if next.isGeometryFlipped { flipped.toggle() }
            current = next.superlayer
        }
        return flipped
    }
}
