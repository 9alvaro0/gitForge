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
        case .history:  return "History"
        case .changes:  return "Changes"
        case .branches: return "Branches"
        case .stashes:  return "Stashes"
        case .pulls:    return "Pull requests"
        case .conflict: return "Conflicts"
        case .settings: return "Settings"
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

    /// Sections shown in the workspace block (top group).
    static let workspaceItems: [WorkspaceSection] = [
        .history, .changes, .branches, .stashes, .pulls, .conflict,
    ]
}
