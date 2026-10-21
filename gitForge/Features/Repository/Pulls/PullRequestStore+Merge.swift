import Foundation

nonisolated enum MergeResult: Equatable, Sendable {
    /// Merged; `warning` when the source branch couldn't be deleted.
    case merged(warning: String?)
    /// New commits arrived since the PR loaded: nothing merged, and the
    /// sheet closes so they get reviewed first.
    case headChanged(String)
    case failed(String)
    /// Nothing to send (no sheet prepared, or a merge already going).
    case ignored
}

extension PullRequestStore {
    /// The banner and Merge…: the host's verdict on the selected PR,
    /// explained with its checks and reviews.
    var mergeReadiness: MergeReadiness? {
        guard let selected, let detail, detail.pull.id == selected.id else { return nil }
        return .evaluate(state: detail.pull.state, mergeable: detail.mergeable, checks: checks,
                         reviewers: detail.reviewers, hostStatus: detail.hostMergeStatus,
                         viewerCanMerge: detail.viewerCanMerge)
    }

    /// Reads what the merge sheet offers and starts a fresh draft: the
    /// options aren't remembered between openings.
    func prepareMerge() async {
        guard let pull = selected, let host, let detail, detail.pull.id == pull.id else { return }
        mergeOptions = nil
        mergeDraft = nil
        mergeOptionsError = nil
        isLoadingMergeOptions = true
        defer { if selected?.id == pull.id { isLoadingMergeOptions = false } }
        let provider = makeReviewProvider(host)
        let commits = commits
        do {
            let options = try await withToken(host) { token in
                try await provider.fetchMergeOptions(host: host, pull: detail.pull, detail: detail, commits: commits, token: token)
            }
            guard selected?.id == pull.id else { return }
            guard let options else {
                mergeOptionsError = String(localized: "The account's token isn't available. Refresh the list.")
                return
            }
            mergeOptions = options
            mergeDraft = MergeDraft(options: options)
        } catch {
            guard selected?.id == pull.id else { return }
            mergeOptionsError = Self.message(for: error)
        }
    }

    /// Merges the selected PR as the sheet's draft says, pinned to the head
    /// the user saw. Only when the host says it can merge; afterwards the
    /// list and the detail reload, and the PR stays selected.
    func merge() async -> MergeResult {
        guard let selectedPull = selected, let host, !isMerging else { return .ignored }
        guard let readiness = mergeReadiness, readiness.canMerge else {
            return .failed(mergeReadiness?.summary ?? MergeReadiness.sentence([HostMergeStatus.notAllowedYet]))
        }
        guard let options = mergeOptions, let draft = mergeDraft else { return .ignored }
        let pull = detail?.pull ?? selectedPull
        let input = draft.input(options: options, headSha: pull.headSha)
        let ref = host.provider.reference(pull.number)

        isMerging = true
        defer { isMerging = false }
        let provider = makeReviewProvider(host)
        do {
            let outcome = try await withToken(host) { token in
                try await provider.merge(host: host, pull: pull, input: input, token: token)
            }
            guard let outcome else {
                return .failed(String(localized: "The account's token isn't available. Refresh the list."))
            }
            if selected?.id == pull.id {
                keepsSelectionOutsideList = true
                mergeDraft = nil
                mergeOptions = nil
            }
            await load(force: true)
            if selected?.id == pull.id {
                await loadDetail()
                if let merged = detail?.pull, merged.id == pull.id { selected = merged }
            }
            let branchKept = input.deleteSourceBranch && !outcome.branchDeleted
            return .merged(warning: branchKept ? String(localized: "Merged \(ref), but \(pull.sourceBranch) couldn't be deleted.") : nil)
        } catch {
            let failure = PullRequestActionError.from(error)
            // The PR moved on the host: show what it is now. The draft stays.
            switch failure {
            case .headChanged, .changedOnHost, .rejected:
                if selected?.id == pull.id { await loadDetail() }
            case .forbidden, .pendingReview, .other:
                break
            }
            let message = failure.message(for: .merge, account: currentUser, host: host.host,
                                          isMergeRequest: host.provider == .gitlab)
            return failure == .headChanged ? .headChanged(message) : .failed(message)
        }
    }
}
