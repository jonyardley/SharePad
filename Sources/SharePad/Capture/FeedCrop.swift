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

    // `canvas` counts rows from the top of the frame; `yUp` says whether the layer
    // that receives the result counts its own y from the bottom.
    func videoFrame(in bounds: CGRect, yUp: Bool) -> CGRect {
        let scale = min(bounds.width / canvas.width, bounds.height / canvas.height)
        let shownWidth = canvas.width * scale
        let shownHeight = canvas.height * scale
        let shownX = bounds.midX - shownWidth / 2
        let shownY = bounds.midY - shownHeight / 2
        let rowsHidden = yUp ? video.height - canvas.maxY : canvas.minY
        return CGRect(
            x: shownX - canvas.minX * scale,
            y: shownY - rowsHidden * scale,
            width: video.width * scale,
            height: video.height * scale
        )
    }
}

// Shows only the sender's canvas rectangle of a decoded feed, so app chrome on the
// iPad never reaches the call (specs/wireless-product.md §4).
final class CroppedVideoLayer: CALayer, @unchecked Sendable {
    let video: AVSampleBufferDisplayLayer

    var crop: FeedCrop? {
        didSet { layoutVideo() }
    }

    init(video: AVSampleBufferDisplayLayer) {
        self.video = video
        super.init()
        masksToBounds = true
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
        } else {
            video.videoGravity = .resizeAspect
            video.frame = bounds
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
