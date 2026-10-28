import Foundation

/// The panes of the Settings mode, in the order of its sidebar.
///
/// The raw values are saved (`settings.lastPane`), so renaming a case sends
/// whoever had it saved back to General. The colors of a pane's tile belong
/// to the view that draws it.
enum SettingsPane: String, CaseIterable, Identifiable {
    case general
    case appearance
    case identities
    case accounts
    case git
    case pullRequests

    var id: String { rawValue }

    var label: String {
        switch self {
        case .general:      return String(localized: "General")
        case .appearance:   return String(localized: "Appearance")
        case .identities:   return String(localized: "Identities")
        case .accounts:     return String(localized: "Accounts")
        case .git:          return "Git"
        case .pullRequests: return String(localized: "Pull requests")
        }
    }

    var symbol: String {
        switch self {
        case .general:      return "gearshape"
        case .appearance:   return "paintpalette"
        case .identities:   return "person.crop.circle"
        case .accounts:     return "key"
        case .git:          return "arrow.triangle.branch"
        case .pullRequests: return WorkspaceSection.pulls.symbol
        }
    }
}
