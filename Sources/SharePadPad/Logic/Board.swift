import CoreGraphics

struct Viewport: Equatable {
    var offset: CGPoint
    var zoom: CGFloat
}

struct BoardPosition: Equatable {
    var centre: CGPoint
    var zoom: CGFloat
}

// Drawing coordinates keep (0, 0) at the old fixed canvas's top left, so saved
// drawings load where they were drawn; the board sits `origin` beyond them.
enum Board {
    static let extent: CGFloat = 20000
    static let origin = CGPoint(x: extent, y: extent)
    static let size = CGSize(width: extent * 2, height: extent * 2)
    static let zoomRange: ClosedRange<CGFloat> = 0.25 ... 4
    static let fitMargin: CGFloat = 48
    static let home = Viewport(offset: origin, zoom: 1)

    static func viewport(for position: BoardPosition, in view: CGSize) -> Viewport {
        let zoom = clampedZoom(position.zoom)
        let offset = CGPoint(
            x: (position.centre.x + origin.x) * zoom - view.width / 2,
            y: (position.centre.y + origin.y) * zoom - view.height / 2
        )
        return Viewport(offset: clamped(offset, zoom: zoom, in: view), zoom: zoom)
    }

    static func position(of viewport: Viewport, in view: CGSize) -> BoardPosition {
        BoardPosition(
            centre: CGPoint(
                x: (viewport.offset.x + view.width / 2) / viewport.zoom - origin.x,
                y: (viewport.offset.y + view.height / 2) / viewport.zoom - origin.y
            ),
            zoom: viewport.zoom
        )
    }

    static func fit(_ drawing: CGRect, in view: CGSize) -> Viewport {
        guard !drawing.isNull, !drawing.isEmpty else { return home }
        let room = CGSize(
            width: max(view.width - fitMargin * 2, 1),
            height: max(view.height - fitMargin * 2, 1)
        )
        let zoom = min(room.width / drawing.width, room.height / drawing.height, 1)
        let centre = CGPoint(x: drawing.midX, y: drawing.midY)
        return viewport(for: BoardPosition(centre: centre, zoom: zoom), in: view)
    }

    private static func clampedZoom(_ zoom: CGFloat) -> CGFloat {
        min(max(zoom, zoomRange.lowerBound), zoomRange.upperBound)
    }

    private static func clamped(_ offset: CGPoint, zoom: CGFloat, in view: CGSize) -> CGPoint {
        let maxX = max(size.width * zoom - view.width, 0)
        let maxY = max(size.height * zoom - view.height, 0)
        return CGPoint(x: min(max(offset.x, 0), maxX), y: min(max(offset.y, 0), maxY))
    }
}
