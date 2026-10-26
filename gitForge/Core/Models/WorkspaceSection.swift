import Foundation

/// Top-level navigation sections shown in the redesigned Sidebar.
enum WorkspaceSection: String, CaseIterable, Identifiable, Sendable {
    case history
    case changes
    case branches
    case stashes
    case pulls
    case conflict
    case settings

    var id: String { rawValue }

    var label: String {
        switch self {
        case .history:  return String(localized: "History")
        case .changes:  return String(localized: "Changes")
        case .branches: return String(localized: "Branches")
        case .stashes:  return String(localized: "Stashes")
        case .pulls:    return String(localized: "Pull requests")
        case .conflict: return String(localized: "Conflicts")
        case .settings: return String(localized: "Settings")
        }
    }

    var symbol: String {
        switch self {
        case .history:  return "clock.arrow.circlepath"
        case .changes:  return "square.and.pencil"
        case .branches: return "arrow.triangle.branch"
        case .stashes:  return "tray.full"
        case .pulls:    return "arrow.triangle.pull"
        case .conflict: return "exclamationmark.triangle"
        case .settings: return "gearshape"
        }
    }

    /// Sections shown in the workspace block (top group), in their default
    /// order. Pull requests is fourth so that ⌘4 keeps opening it for whoever
    /// uses it today (pulls-unified §4.7); the order a person keeps lives in
    /// `SidebarOrder`.
    static let workspaceItems: [WorkspaceSection] = [
        .history, .changes, .branches, .pulls, .stashes, .conflict,
    ]
}
