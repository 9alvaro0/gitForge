import Foundation

extension PullRequestStore {
    /// Selects `pull`, unless it's the one open, and asks its detail to open
    /// `action`'s panel or sheet once loaded (`takeQuickAction`).
    func requestQuickAction(_ action: PullQuickAction, on pull: PullRequest) {
        if selected?.number != pull.number { select(pull) }
        pendingQuickAction = PendingPullQuickAction(pullNumber: pull.number, action: action)
    }

    /// What the detail view watches to call `takeQuickAction` again.
    var quickActionCheckpoint: QuickActionCheckpoint {
        QuickActionCheckpoint(pending: pendingQuickAction, selectedID: selected?.id, detailID: detail?.pull.id,
                              isLoadingDetail: isLoadingDetail, hasDetailError: detailError != nil)
    }

    /// The pending quick action, once the selected pull request's detail has
    /// loaded: what it comes to, and it's taken off. While the detail loads,
    /// `nil` and it stays. It goes with nothing to say when another pull
    /// request is selected or the detail couldn't load (the detail shows
    /// why); when the detail doesn't allow it after all (already approved,
    /// merging blocked), `.refused` with the reason.
    func takeQuickAction() -> QuickActionOutcome? {
        guard let pending = pendingQuickAction else { return nil }
        guard let selected, selected.number == pending.pullNumber else {
            pendingQuickAction = nil
            return nil
        }
        guard !isLoadingDetail else { return nil }
        guard let detail, detail.pull.id == selected.id else {
            // Not loaded yet (the load hasn't started), or it failed.
            if detailError != nil { pendingQuickAction = nil }
            return nil
        }
        pendingQuickAction = nil
        switch pending.action {
        case .approve:
            if isReviewBusy { return .refused(String(localized: "A review is already being sent.")) }
            switch reviewActions.approve {
            case .available: return .perform(.approve)
            case .approved: return .refused(String(localized: "You've already approved it."))
            case .hidden: return .refused(String(localized: "You can't approve it."))
            }
        case .merge:
            let state = detail.pull.state
            guard state == .open || state == .draft else {
                return .refused(String(localized: "It's no longer open."))
            }
            if isMerging { return .refused(String(localized: "It's already being merged.")) }
            if let reason = mergeBlockedReason { return .refused(String(localized: "Can't merge yet. \(reason)")) }
            return .perform(.merge)
        }
    }
}
