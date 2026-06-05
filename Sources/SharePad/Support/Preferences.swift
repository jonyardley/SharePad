import CoreGraphics
import Foundation

struct Preferences {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var autoShowOnConnect: Bool {
        get { defaults.object(forKey: Key.autoShowOnConnect) as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: Key.autoShowOnConnect) }
    }

    var keepOnTop: Bool {
        get { defaults.object(forKey: Key.keepOnTop) as? Bool ?? false }
        nonmutating set { defaults.set(newValue, forKey: Key.keepOnTop) }
    }

    var lastDeviceID: String? {
        get { defaults.string(forKey: Key.lastDeviceID) }
        nonmutating set { defaults.set(newValue, forKey: Key.lastDeviceID) }
    }

    var windowOrigin: CGPoint? {
        get {
            guard let originX = defaults.object(forKey: Key.windowOriginX) as? Double,
                  let originY = defaults.object(forKey: Key.windowOriginY) as? Double
            else { return nil }
            return CGPoint(x: originX, y: originY)
        }
        nonmutating set {
            guard let newValue else {
                defaults.removeObject(forKey: Key.windowOriginX)
                defaults.removeObject(forKey: Key.windowOriginY)
                return
            }
            defaults.set(Double(newValue.x), forKey: Key.windowOriginX)
            defaults.set(Double(newValue.y), forKey: Key.windowOriginY)
        }
    }

    var windowLongSide: CGFloat? {
        get {
            guard let value = defaults.object(forKey: Key.windowLongSide) as? Double
            else { return nil }
            return CGFloat(value)
        }
        nonmutating set {
            guard let newValue else {
                defaults.removeObject(forKey: Key.windowLongSide)
                return
            }
            defaults.set(Double(newValue), forKey: Key.windowLongSide)
        }
    }

    var firstLaunchDate: Date? {
        get { defaults.object(forKey: Key.firstLaunch) as? Date }
        nonmutating set { defaults.set(newValue, forKey: Key.firstLaunch) }
    }

    var licenseName: String? {
        get { defaults.string(forKey: Key.licenseName) }
        nonmutating set { defaults.set(newValue, forKey: Key.licenseName) }
    }

    var licenseKey: String? {
        get { defaults.string(forKey: Key.licenseKey) }
        nonmutating set { defaults.set(newValue, forKey: Key.licenseKey) }
    }

    private enum Key {
        static let autoShowOnConnect = "autoShowOnConnect"
        static let keepOnTop = "keepOnTop"
        static let lastDeviceID = "lastDeviceID"
        static let windowOriginX = "windowOriginX"
        static let windowOriginY = "windowOriginY"
        static let windowLongSide = "windowLongSide"
        // Deliberately non-obvious key name — a small bump against a casual trial reset.
        static let firstLaunch = "configRevisionDate"
        static let licenseName = "licenseName"
        static let licenseKey = "licenseKey"
    }
}
