import Foundation

/// A shortcut a pull request's row offers. The row only asks: the detail
/// carries it out once it has loaded, with the same panel or sheet as the
/// header's button, so nothing is sent without that last step.
nonisolated enum PullQuickAction: Equatable, Sendable {
    /// The Approve panel, for its optional comment.
    case approve
    /// The merge sheet.
    case merge
}

/// What a row's quick action comes to once its detail has loaded.
nonisolated enum QuickActionOutcome: Equatable, Sendable {
    /// Open the action's panel or sheet.
    case perform(PullQuickAction)
    /// The detail doesn't allow it after all: why, for a toast.
    case refused(String)
}

/// A row's quick action waiting for its detail (`PullRequestStore.takeQuickAction`).
nonisolated struct PendingPullQuickAction: Equatable, Sendable {
    let pullNumber: Int
    let action: PullQuickAction
}

/// An inbox row's quick action waiting for its repo's detail store to open
/// the pull request (`ReviewsStore.forwardQuickAction`).
nonisolated struct PendingInboxQuickAction: Equatable, Sendable {
    let itemID: InboxPull.ID
    let action: PullQuickAction
}

/// Where a pending quick action stands, for the detail to look again each
/// time it moves.
nonisolated struct QuickActionCheckpoint: Equatable, Sendable {
    let pending: PendingPullQuickAction?
    let selectedID: String?
    let detailID: String?
    let isLoadingDetail: Bool
    let hasDetailError: Bool
}
