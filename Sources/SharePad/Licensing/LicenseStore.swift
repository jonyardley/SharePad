import Foundation

struct LicenseStore {
    private let preferences: Preferences

    init(preferences: Preferences) {
        self.preferences = preferences
    }

    func firstLaunch(now: Date) -> Date {
        if let existing = preferences.firstLaunchDate { return existing }
        preferences.firstLaunchDate = now
        return now
    }

    var name: String? {
        preferences.licenseName
    }

    var key: String? {
        preferences.licenseKey
    }

    func save(name: String, key: String) {
        preferences.licenseName = name
        preferences.licenseKey = key
    }
}
