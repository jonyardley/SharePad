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

    private enum Key {
        static let autoShowOnConnect = "autoShowOnConnect"
        static let keepOnTop = "keepOnTop"
        static let lastDeviceID = "lastDeviceID"
    }
}
