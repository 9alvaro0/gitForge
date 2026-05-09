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

    var label: String {
        switch state {
        case .open:   "Open"
        case .closed: "Closed"
        case .merged: "Merged"
        case .draft:  "Draft"
        }
    }
}
