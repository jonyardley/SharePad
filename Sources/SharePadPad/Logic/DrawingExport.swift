import CoreGraphics
import Foundation

enum ExportFormat: String, CaseIterable, Sendable {
    case png
    case pdf

    var title: String {
        switch self {
        case .png: "Image (PNG)"
        case .pdf: "PDF"
        }
    }
}

struct DrawingExport: Equatable {
    static let margin: CGFloat = 48
    static let preferredScale: CGFloat = 2
    static let maximumPixels: CGFloat = 4096
    // ISO 32000-1 Annex C caps a page at 14400 units a side.
    static let maximumPage: CGFloat = 14400

    let area: CGRect
    let scale: CGFloat
    let pageSize: CGSize

    init?(drawingBounds bounds: CGRect) {
        guard !bounds.isNull, !bounds.isInfinite, !bounds.isEmpty else { return nil }
        area = bounds.insetBy(dx: -Self.margin, dy: -Self.margin).integral
        let longest = max(area.width, area.height)
        scale = min(Self.preferredScale, Self.maximumPixels / longest)
        let fit = min(1, Self.maximumPage / longest)
        pageSize = CGSize(width: area.width * fit, height: area.height * fit)
    }

    var pixelSize: CGSize {
        CGSize(width: (area.width * scale).rounded(), height: (area.height * scale).rounded())
    }

    // Below 1x the paper is drawn zoomed out, so PaperGrid widens its gap as on
    // screen instead of shrinking the lines to a grey wash.
    var paperZoom: CGFloat {
        min(1, scale)
    }

    var paperViewport: Viewport {
        Viewport(
            offset: CGPoint(
                x: (area.minX + Board.origin.x) * paperZoom,
                y: (area.minY + Board.origin.y) * paperZoom
            ),
            zoom: paperZoom
        )
    }

    static func fileName(
        for format: ExportFormat,
        at date: Date,
        in timeZone: TimeZone = .current
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm"
        return "SharePad \(formatter.string(from: date)).\(format.rawValue)"
    }
}
