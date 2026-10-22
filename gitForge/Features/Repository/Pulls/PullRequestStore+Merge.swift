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

    /// Why Merge… can't go ahead, as the banner says it; `nil` when it can.
    var mergeBlockedReason: String? {
        guard mergeReadiness?.canMerge != true else { return nil }
        return mergeReadiness?.summary ?? MergeReadiness.sentence([HostMergeStatus.notAllowedYet])
    }

    /// What the open sheet says under its fields: why it can't merge now.
    /// Nothing while a merge is going: once it lands the PR reads as merged,
    /// with no verdict to give, until the sheet closes.
    var mergeSheetBlockedReason: String? {
        guard mergeDraft != nil, !isMerging else { return nil }
        return mergeBlockedReason
    }

    /// The sheet closed: its options go, and a read still in flight lands
    /// nowhere, so the next opening reads them afresh.
    func discardMergeOptions() {
        mergeOptionsGen &+= 1
        mergeOptions = nil
        mergeDraft = nil
        mergeOptionsError = nil
        isLoadingMergeOptions = false
    }

    /// Reads what the merge sheet offers and starts a fresh draft: the
    /// options aren't remembered between openings.
    func prepareMerge() async {
        guard let pull = selected, let host, let detail, detail.pull.id == pull.id else { return }
        mergeOptionsGen &+= 1
        let gen = mergeOptionsGen
        mergeOptions = nil
        mergeDraft = nil
        mergeOptionsError = nil
        isLoadingMergeOptions = true
        defer { if gen == mergeOptionsGen { isLoadingMergeOptions = false } }
        let provider = makeReviewProvider(host)
        let commits = commits
        do {
            let options = try await withToken(host) { token in
                try await provider.fetchMergeOptions(host: host, pull: detail.pull, detail: detail, commits: commits, token: token)
            }
            guard gen == mergeOptionsGen else { return }
            guard let options else {
                mergeOptionsError = String(localized: "The account's token isn't available. Refresh the list.")
                return
            }
            mergeOptions = options
            mergeDraft = MergeDraft(options: options)
        } catch {
            guard gen == mergeOptionsGen else { return }
            mergeOptionsError = Self.message(for: error)
        }
    }

    /// Merges the selected PR as the sheet's draft says, pinned to the head
    /// the user saw. Only when the host says it can merge; afterwards the
    /// list (if it was ever loaded) and the detail reload, and the PR stays
    /// selected.
    func merge() async -> MergeResult {
        guard let selectedPull = selected, let host, !isMerging else { return .ignored }
        let pull = detail?.pull ?? selectedPull
        if let reason = mergeBlockedReason { return .failed(Self.naming(pull, on: host, reason)) }
        guard let options = mergeOptions, let draft = mergeDraft else { return .ignored }
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
                return .failed(Self.naming(pull, on: host, String(localized: "The account's token isn't available. Refresh the list.")))
            }
            if selected?.id == pull.id {
                keepsSelectionOutsideList = true
                // Merged, whatever the reloads below manage to read back.
                selected?.state = .merged
                if detail?.pull.id == pull.id { detail?.pull.state = .merged }
            }
            // A store that only opened the detail (Reviews) has no list to
            // bring up to date: its screen reads the repo again itself.
            if lastLoadedAt != nil { await load(force: true) }
            if selected?.id == pull.id {
                await loadDetail()
                if let merged = detail?.pull, merged.id == pull.id { selected = merged }
                // The sheet stays open through the reloads: its fields go
                // only now, as it closes.
                mergeDraft = nil
                mergeOptions = nil
            }
            let branchKept = input.deleteSourceBranch && !outcome.branchDeleted
            return .merged(warning: branchKept ? String(localized: "Merged \(ref), but \(pull.sourceBranch) couldn't be deleted.") : nil)
        } catch {
            var failure = PullRequestActionError.from(error)
            // An open PR doesn't vanish: a 404 on merge is the host hiding
            // what the account can't touch.
            if failure == .changedOnHost { failure = .forbidden }
            // The PR moved on the host: show what it is now. The sheet keeps
            // the draft, unless new commits close it.
            switch failure {
            case .headChanged, .changedOnHost, .rejected:
                if selected?.id == pull.id { await loadDetail() }
            case .forbidden, .pendingReview, .other:
                break
            }
            let message = Self.naming(pull, on: host, failure.message(for: .merge, account: currentUser, host: host.host,
                                                                      isMergeRequest: host.provider == .gitlab))
            return failure == .headChanged ? .headChanged(message) : .failed(message)
        }
    }
}
