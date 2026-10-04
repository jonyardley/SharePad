import CoreGraphics
import Foundation

enum PaperStyle: String, CaseIterable, Sendable {
    case plain
    case grid
    case dots

    var title: String {
        switch self {
        case .plain: "Plain"
        case .grid: "Grid"
        case .dots: "Dots"
        }
    }
}

enum PaperTone: String, CaseIterable, Sendable {
    case light
    case dark

    var title: String {
        switch self {
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}

struct Paper: Equatable, Sendable {
    var style: PaperStyle = .plain
    var tone: PaperTone = .light
}

struct PadPreferences {
    private enum Key {
        static let paperStyle = "paperStyle"
        static let paperTone = "paperTone"
        static let lastMac = "lastMac"
        static let boardX = "boardCentreX"
        static let boardY = "boardCentreY"
        static let boardZoom = "boardZoom"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var paper: Paper {
        get {
            Paper(
                style: defaults.string(forKey: Key.paperStyle).flatMap(PaperStyle.init) ?? .plain,
                tone: defaults.string(forKey: Key.paperTone).flatMap(PaperTone.init) ?? .light
            )
        }
        nonmutating set {
            defaults.set(newValue.style.rawValue, forKey: Key.paperStyle)
            defaults.set(newValue.tone.rawValue, forKey: Key.paperTone)
        }
    }

    var boardPosition: BoardPosition? {
        get {
            guard defaults.object(forKey: Key.boardZoom) != nil else { return nil }
            return BoardPosition(
                centre: CGPoint(
                    x: defaults.double(forKey: Key.boardX),
                    y: defaults.double(forKey: Key.boardY)
                ),
                zoom: defaults.double(forKey: Key.boardZoom)
            )
        }
        nonmutating set {
            guard let newValue else {
                [Key.boardX, Key.boardY, Key.boardZoom].forEach(defaults.removeObject)
                return
            }
            defaults.set(Double(newValue.centre.x), forKey: Key.boardX)
            defaults.set(Double(newValue.centre.y), forKey: Key.boardY)
            defaults.set(Double(newValue.zoom), forKey: Key.boardZoom)
        }
    }

    var lastMac: String? {
        get { defaults.string(forKey: Key.lastMac) }
        nonmutating set { defaults.set(newValue, forKey: Key.lastMac) }
    }
}
