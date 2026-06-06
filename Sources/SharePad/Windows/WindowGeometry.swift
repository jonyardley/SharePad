import CoreGraphics

/// Placeholder content size used before any video frame has reported real dimensions
/// (and as the window's throwaway initial frame). Replaced as soon as a frame arrives.
let fallbackContentSize = CGSize(width: 600, height: 800)

func fittedContentSize(for videoSize: CGSize, maxLongSide: CGFloat = 900) -> CGSize {
    let longSide = max(videoSize.width, videoSize.height)
    guard longSide > 0 else { return fallbackContentSize }
    let scale = min(1, maxLongSide / longSide)
    return CGSize(width: videoSize.width * scale, height: videoSize.height * scale)
}

/// nil means the saved frame's monitor is gone — the caller should centre instead.
func placedOrigin(savedOrigin: CGPoint, size: CGSize, onScreens screens: [CGRect]) -> CGPoint? {
    let rect = CGRect(origin: savedOrigin, size: size)
    guard let screen = screens.max(by: { intersectionArea($0, rect) < intersectionArea($1, rect) }),
          intersectionArea(screen, rect) > 0
    else { return nil }
    return clamped(savedOrigin, size: size, within: screen)
}

func centeredResizeOrigin(oldFrame: CGRect, newSize: CGSize,
                          onScreens screens: [CGRect]) -> CGPoint {
    let center = CGPoint(x: oldFrame.midX, y: oldFrame.midY)
    let origin = CGPoint(x: center.x - newSize.width / 2, y: center.y - newSize.height / 2)
    return placedOrigin(savedOrigin: origin, size: newSize, onScreens: screens) ?? origin
}

private func intersectionArea(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
    let overlap = lhs.intersection(rhs)
    return overlap.isNull ? 0 : overlap.width * overlap.height
}

private func clamped(_ origin: CGPoint, size: CGSize, within screen: CGRect) -> CGPoint {
    let maxX = max(screen.minX, screen.maxX - size.width)
    let maxY = max(screen.minY, screen.maxY - size.height)
    return CGPoint(
        x: min(max(origin.x, screen.minX), maxX),
        y: min(max(origin.y, screen.minY), maxY)
    )
}
