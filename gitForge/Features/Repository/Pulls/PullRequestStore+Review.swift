import SwiftUI

/// Text the user is writing in a review box. Kept in the store, keyed by PR,
/// so a reload or switching PRs doesn't lose it.
nonisolated enum ReviewDraftKey: Hashable, Sendable {
    case review(pullId: String, ReviewVerdict)
    case reply(pullId: String, threadId: String)
    case comment(pullId: String, target: CommentTarget)
}

/// What the user is typing in the review boxes, one observed box per
/// draft: a keystroke redraws only the views that read that draft, not
/// every "Reply…" field on screen.
@MainActor
final class ReviewDrafts {
    @Observable @MainActor
    final class Box {
        var text: String?
    }

    private var boxes: [ReviewDraftKey: Box] = [:]

    subscript(key: ReviewDraftKey) -> String? {
        get { box(key).text }
        set {
            let box = box(key)
            if box.text != newValue { box.text = newValue }
        }
    }

    /// Every draft goes (a repo switch).
    func removeAll() {
        for box in boxes.values where box.text != nil { box.text = nil }
    }

    /// Made on the first read too, so a view that read a draft before it
    /// was written hears its first write.
    private func box(_ key: ReviewDraftKey) -> Box {
        if let box = boxes[key] { return box }
        let box = Box()
        boxes[key] = box
        return box
    }
}

nonisolated enum ReviewSubmitResult: Equatable, Sendable {
    /// Landed; `warning` when its comment didn't (GitLab posts it apart).
    case submitted(warning: String?)
    case failed(String)
    /// Nothing to send (no PR, an empty "Request changes", one already going).
    case ignored
}

extension PullRequestStore {
    var reviewActions: ReviewActions {
        guard let pull = selected, let host else { return .hidden }
        let current = detail?.pull.id == pull.id ? detail : nil
        return .resolve(provider: host.provider, pull: current?.pull ?? pull, currentUser: currentUser,
                        reviewers: current?.reviewers ?? [], viewerApproval: current?.viewerApproval,
                        requestChanges: requestChangesSupport)
    }

    /// The review buttons are off: a review is going, or the selected PR's
    /// detail is still reloading after one (it may say "Approved" by then).
    var isReviewBusy: Bool {
        submittingReview != nil || (reviewSettlingPullId != nil && reviewSettlingPullId == selected?.id)
    }

    func draftBinding(_ key: ReviewDraftKey) -> Binding<String> {
        Binding(get: { self.drafts[key] ?? "" }, set: { self.drafts[key] = $0 })
    }

    /// Approves or requests changes on the selected PR with its draft as the
    /// comment. The PR is captured up front: switching PRs mid-flight
    /// doesn't redirect the review, and only reloads the detail it belongs to.
    /// It answers as soon as the host does; the reload follows on its own.
    func submitReview(_ verdict: ReviewVerdict) async -> ReviewSubmitResult {
        guard let selectedPull = selected, let host, !isReviewBusy else { return .ignored }
        let pull = detail?.pull.id == selectedPull.id ? (detail?.pull ?? selectedPull) : selectedPull
        let key = ReviewDraftKey.review(pullId: pull.id, verdict)
        let body = drafts[key] ?? ""
        if verdict == .requestChanges, body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .ignored }

        submittingReview = verdict
        defer { submittingReview = nil }
        let provider = makeReviewProvider(host)
        do {
            let outcome = try await withToken(host) { token in
                try await provider.submitReview(host: host, pull: pull, verdict: verdict, body: body, token: token)
            }
            guard let warning = outcome else {
                return .failed(Self.naming(pull, on: host, String(localized: "The account's token isn't available. Refresh the list.")))
            }
            // A comment that didn't post stays as a draft so it isn't lost.
            if warning == nil { drafts[key] = nil }
            if selected?.id == pull.id {
                reviewPanel = nil
                settle(pull)
            }
            return .submitted(warning: warning.map { Self.naming(pull, on: host, $0) })
        } catch {
            let failure = PullRequestActionError.from(error)
            // The PR moved on the host: show what it is now. The draft stays.
            switch failure {
            case .headChanged, .changedOnHost, .rejected:
                if selected?.id == pull.id { settle(pull) }
            case .forbidden, .pendingReview, .other:
                break
            }
            let action: PullRequestAction = verdict == .approve ? .approve : .requestChanges
            return .failed(Self.naming(pull, on: host, failure.message(for: action, account: currentUser, host: host.host,
                                                                      isMergeRequest: host.provider == .gitlab)))
        }
    }

    /// Reloads `pull`'s detail in the background, the review buttons off
    /// until it's in: until then they'd offer what was just done.
    private func settle(_ pull: PullRequest) {
        reviewSettlingPullId = pull.id
        reloadDetailInBackground { [weak self] in
            if self?.reviewSettlingPullId == pull.id { self?.reviewSettlingPullId = nil }
        }
    }

    /// The open panel's action is gone (the PR merged or closed, or the
    /// host no longer takes it): the panel goes too, its draft stays.
    func closeReviewPanelIfGone() {
        guard let verdict = reviewPanel else { return }
        let actions = reviewActions
        let offered = verdict == .approve ? actions.approve == .available : actions.requestChanges == .available
        if !offered { reviewPanel = nil }
    }
}
