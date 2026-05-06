import Foundation

/// Top-level navigation sections shown in the redesigned Sidebar.
enum WorkspaceSection: String, CaseIterable, Identifiable, Sendable {
    case history
    case changes
    case branches
    case pulls
    case conflict
    case blame
    case terminal
    case clone
    case settings

    var id: String { rawValue }

    var label: String {
        switch self {
        case .history:  return "History"
        case .changes:  return "Changes"
        case .branches: return "Branches"
        case .pulls:    return "Pull requests"
        case .conflict: return "Conflicts"
        case .blame:    return "Blame"
        case .terminal: return "Terminal"
        case .clone:    return "Clone repo…"
        case .settings: return "Settings"
        }
    }

    var icon: GFIconKind {
        switch self {
        case .history:  return .graph
        case .changes:  return .diff
        case .branches: return .branch
        case .pulls:    return .pr
        case .conflict: return .conflict
        case .blame:    return .blame
        case .terminal: return .terminal
        case .clone:    return .clone
        case .settings: return .settings
        }
    }

    /// Sections shown in the workspace block (top group).
    static let workspaceItems: [WorkspaceSection] = [
        .history, .changes, .branches, .pulls, .conflict, .blame, .terminal,
    ]

    /// Sections shown in the bottom group of the sidebar.
    static let bottomItems: [WorkspaceSection] = [.clone, .settings]
}
