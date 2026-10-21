import Foundation

/// Which review buttons the detail header shows, and in which state.
nonisolated struct ReviewActions: Equatable, Sendable {
    enum Approve: Equatable, Sendable {
        case hidden, available
        /// Already approved by the signed-in user: shown, disabled.
        case approved
    }

    enum RequestChanges: Equatable, Sendable {
        case hidden, available
        /// Shown disabled, with the reason as its help.
        case unavailable(reason: String)
    }

    let approve: Approve
    let requestChanges: RequestChanges

    /// No review buttons (closed, merged, your own PR, no rights).
    static let hidden = ReviewActions(approve: .hidden, requestChanges: .hidden)

    /// GitHub won't let you review your own PR, and GitLab says per user
    /// whether you may approve; neither applies once the PR is closed.
    static func resolve(provider: RemoteProvider, pull: PullRequest, currentUser: String?,
                        reviewers: [PullRequestDetail.Reviewer], viewerApproval: ViewerApproval?,
                        requestChanges: RequestChangesSupport?) -> ReviewActions {
        guard pull.state == .open || pull.state == .draft else { return .hidden }
        if let currentUser, pull.authorLogin == currentUser { return .hidden }
        switch provider {
        case .github:
            let approvedByYou = currentUser.map { user in
                reviewers.contains { $0.login == user && $0.state == .approved }
            } ?? false
            return ReviewActions(approve: approvedByYou ? .approved : .available, requestChanges: .available)
        case .gitlab:
            if let viewerApproval, !viewerApproval.canApprove, !viewerApproval.hasApproved { return .hidden }
            let requestChangesState: RequestChanges = switch requestChanges {
            case nil: .hidden
            case .supported: .available
            case .unsupported(let reason): .unavailable(reason: reason)
            }
            return ReviewActions(approve: viewerApproval?.hasApproved == true ? .approved : .available,
                                 requestChanges: requestChangesState)
        }
    }
}
