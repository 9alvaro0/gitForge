import SwiftUI

enum ThemeMode: String, CaseIterable, Identifiable, Sendable {
    case system
    case dark
    case light

    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: return String(localized: "System")
        case .dark:   return String(localized: "Dark")
        case .light:  return String(localized: "Light")
        }
    }
}
