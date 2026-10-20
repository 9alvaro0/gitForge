import Foundation

/// Provider-agnostic representation of a GitHub pull request or a GitLab
/// merge request. Both APIs are mapped onto this model so the UI never has
/// to branch on provider.
nonisolated struct PullRequest: Sendable, Equatable, Identifiable {
    enum State: Sendable, Equatable {
        case open
        case closed
        case merged
        case draft
    }

    let id: String           // provider-specific stable id (number or "iid:...")
    let number: Int          // user-visible number (#42)
    let title: String
    let state: State
    let authorLogin: String?
    let authorAvatarURL: URL?
    let sourceBranch: String
    let targetBranch: String
    let webURL: URL?
    let createdAt: Date?
    let updatedAt: Date?
    /// SHA of the source branch tip; CI checks are looked up by it.
    var headSha: String? = nil

    var label: String {
        switch state {
        case .open:   String(localized: "pr.state.open", defaultValue: "Open")
        case .closed: String(localized: "pr.state.closed", defaultValue: "Closed")
        case .merged: String(localized: "pr.state.merged", defaultValue: "Merged")
        case .draft:  String(localized: "pr.state.draft", defaultValue: "Draft")
        }
    }
}

/// Which pull requests the list shows.
nonisolated enum PullListScope: String, CaseIterable, Identifiable, Sendable {
    case open, mine, closed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .open: String(localized: "pr.scope.open", defaultValue: "Open")
        case .mine: String(localized: "pr.scope.mine", defaultValue: "Mine")
        case .closed: String(localized: "pr.scope.closed", defaultValue: "Closed")
        }
    }
}

/// What a provider list request asks for. "Mine" is the open list filtered
/// locally by author, so it doesn't need its own request.
nonisolated enum PullListState: Sendable {
    case open, closed
}
