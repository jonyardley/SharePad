import CoreGraphics
import ImageIO
import SharePadWire

struct CanvasLayout: Equatable, Sendable {
    var canvas: CGRect
    var window: CGSize
    var obstructions: [CGRect] = []
}

enum CanvasCrop {
    static func shareableRect(of layout: CanvasLayout) -> CGRect {
        layout.obstructions.reduce(layout.canvas) { area, obstruction in
            largestFreeStrip(of: area, avoiding: obstruction)
        }
    }

    static func largestFreeStrip(of area: CGRect, avoiding obstruction: CGRect) -> CGRect {
        let overlap = area.intersection(obstruction)
        guard !overlap.isNull, overlap.width > 0, overlap.height > 0 else { return area }
        let candidates = [
            CGRect(x: area.minX, y: area.minY, width: area.width, height: overlap.minY - area.minY),
            CGRect(
                x: area.minX,
                y: overlap.maxY,
                width: area.width,
                height: area.maxY - overlap.maxY
            ),
            CGRect(
                x: area.minX,
                y: area.minY,
                width: overlap.minX - area.minX,
                height: area.height
            ),
            CGRect(
                x: overlap.maxX,
                y: area.minY,
                width: area.maxX - overlap.maxX,
                height: area.height
            ),
        ]
        return candidates.max { $0.width * $0.height < $1.width * $1.height } ?? .zero
    }

    static func pixelRect(
        for layout: CanvasLayout,
        bufferWidth: Int,
        bufferHeight: Int,
        orientation: CGImagePropertyOrientation
    ) -> CanvasRect? {
        let area = shareableRect(of: layout)
        guard layout.window.width > 0, layout.window.height > 0,
              area.width > 0, area.height > 0
        else { return nil }
        let rotated = orientation == .left || orientation == .right
        let displayWidth = CGFloat(rotated ? bufferHeight : bufferWidth)
        let displayHeight = CGFloat(rotated ? bufferWidth : bufferHeight)
        let scaled = CGRect(
            x: area.minX * displayWidth / layout.window.width,
            y: area.minY * displayHeight / layout.window.height,
            width: area.width * displayWidth / layout.window.width,
            height: area.height * displayHeight / layout.window.height
        )
        let stored = storedRect(
            scaled,
            orientation: orientation,
            bufferWidth: CGFloat(bufferWidth),
            bufferHeight: CGFloat(bufferHeight)
        )
        let bounded = stored.intersection(CGRect(
            x: 0,
            y: 0,
            width: bufferWidth,
            height: bufferHeight
        ))
        guard !bounded.isNull else { return nil }
        return canvasRect(inward(bounded))
    }

    // Rounding outward would let a pixel row of the bar or tool picker into the share.
    private static func inward(_ rect: CGRect) -> CGRect {
        let minX = rect.minX.rounded(.up)
        let minY = rect.minY.rounded(.up)
        return CGRect(
            x: minX,
            y: minY,
            width: rect.maxX.rounded(.down) - minX,
            height: rect.maxY.rounded(.down) - minY
        )
    }

    // EXIF orientation names the rotation that turns the stored buffer upright; the
    // crop has to be expressed in the stored buffer's own pixels.
    private static func storedRect(
        _ rect: CGRect,
        orientation: CGImagePropertyOrientation,
        bufferWidth: CGFloat,
        bufferHeight: CGFloat
    ) -> CGRect {
        switch orientation {
        case .right:
            CGRect(
                x: rect.minY,
                y: bufferHeight - rect.maxX,
                width: rect.height,
                height: rect.width
            )
        case .left:
            CGRect(x: bufferWidth - rect.maxY, y: rect.minX, width: rect.height, height: rect.width)
        case .down:
            CGRect(
                x: bufferWidth - rect.maxX,
                y: bufferHeight - rect.maxY,
                width: rect.width,
                height: rect.height
            )
        default:
            rect
        }
    }

    private static func canvasRect(_ rect: CGRect) -> CanvasRect? {
        guard !rect.isNull, rect.width > 0, rect.height > 0 else { return nil }
        return CanvasRect(
            x: UInt32(rect.minX),
            y: UInt32(rect.minY),
            width: UInt32(rect.width),
            height: UInt32(rect.height)
        )
    }
}
