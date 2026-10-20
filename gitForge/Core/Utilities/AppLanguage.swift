import Foundation

/// Languages the app ships in. `nil` (see `AppLanguageStore`) means "follow
/// the system", which is the default.
nonisolated enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case english = "en"
    case spanish = "es"
    case portuguese = "pt-PT"

    var id: String { rawValue }

    /// Each language in its own name, so it's recognisable whatever language
    /// the UI is in right now.
    var nativeName: String {
        switch self {
        case .english:    "English"
        case .spanish:    "Español"
        case .portuguese: "Português (Portugal)"
        }
    }
}

/// Per-app language override. Writes `AppleLanguages` into the app's own
/// defaults domain (the same thing System Settings › Language & Region › Apps
/// does), so it takes effect on the next launch.
nonisolated struct AppLanguageStore {
    static let key = "AppleLanguages"

    let defaults: UserDefaults
    /// Domain the override lives in: the bundle identifier for the real app,
    /// the suite name in tests.
    let domain: String

    init(defaults: UserDefaults = .standard, domain: String = Bundle.main.bundleIdentifier ?? "") {
        self.defaults = defaults
        self.domain = domain
    }

    /// The app-level override, or `nil` when the app follows the system.
    /// Reads the app's own domain only: `defaults.array(forKey:)` would also
    /// return the global system list.
    var override: AppLanguage? {
        guard let codes = defaults.persistentDomain(forName: domain)?[Self.key] as? [String],
              let first = codes.first else { return nil }
        return AppLanguage(rawValue: first)
    }

    func setOverride(_ language: AppLanguage?) {
        if let language {
            defaults.set([language.rawValue], forKey: Self.key)
        } else {
            defaults.removeObject(forKey: Self.key)
        }
    }
}
