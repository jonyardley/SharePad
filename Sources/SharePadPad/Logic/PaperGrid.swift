import CoreGraphics

struct PaperGrid: Equatable {
    let columns: [CGFloat]
    let rows: [CGFloat]

    // Zoomed out, the gap doubles until it is at least `minimumGap`, so the
    // paper thins out instead of turning into a grey wash.
    init(spacing: CGFloat, minimumGap: CGFloat, viewport: Viewport, size: CGSize) {
        var gap = spacing
        while gap * viewport.zoom < minimumGap {
            gap *= 2
        }
        columns = Self.lines(
            gap: gap, origin: Board.origin.x, offset: viewport.offset.x,
            zoom: viewport.zoom, length: size.width
        )
        rows = Self.lines(
            gap: gap, origin: Board.origin.y, offset: viewport.offset.y,
            zoom: viewport.zoom, length: size.height
        )
    }

    private static func lines(
        gap: CGFloat, origin: CGFloat, offset: CGFloat, zoom: CGFloat, length: CGFloat
    ) -> [CGFloat] {
        let first = Int(((offset / zoom - origin) / gap).rounded(.up))
        let last = Int((((offset + length) / zoom - origin) / gap).rounded(.down))
        guard first <= last else { return [] }
        return (first ... last)
            .map { (origin + CGFloat($0) * gap) * zoom - offset }
            .filter { $0 > 0 && $0 < length }
    }
}
