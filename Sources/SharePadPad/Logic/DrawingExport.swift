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
    static let maximumPixels: CGFloat = 6144
    // Acrobat and Preview refuse pages beyond 200 inches (14400 points) a side.
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

    var paperViewport: Viewport {
        Viewport(
            offset: CGPoint(x: area.minX + Board.origin.x, y: area.minY + Board.origin.y),
            zoom: 1
        )
    }

    static func fileName(
        for format: ExportFormat,
        at date: Date,
        in timeZone: TimeZone = .current
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm"
        return "SharePad \(formatter.string(from: date)).\(format.rawValue)"
    }
}
