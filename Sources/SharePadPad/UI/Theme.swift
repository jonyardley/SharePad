import SwiftUI

enum Theme {
    enum Spacing {
        static let tight: CGFloat = 6
        static let row: CGFloat = 12
        static let bar: CGFloat = 16
    }

    enum Paper {
        static let gridSpacing: CGFloat = 32
        static let dotDiameter: CGFloat = 3
        static let lineWidth: CGFloat = 0.5

        static func surface(_ tone: PaperTone) -> Color {
            tone == .dark ? Color(white: 0.12) : .white
        }

        static func marking(_ tone: PaperTone) -> Color {
            tone == .dark ? Color(white: 1, opacity: 0.18) : Color(white: 0, opacity: 0.14)
        }
    }

    enum Status {
        static func colour(_ tone: ConnectionPill.Tone) -> Color {
            switch tone {
            case .live: .green
            case .waiting: .secondary
            case .attention: .orange
            }
        }
    }
}
