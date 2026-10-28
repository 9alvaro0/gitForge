import Foundation

extension RepositoryViewModel {
    /// How a checkout started from the UI ended.
    enum CheckoutOutcome: Sendable, Equatable {
        /// Checked out; the toast that confirms it.
        case done(String)
        /// git refused over local changes in the way and `blockedCheckout`
        /// asks whether to stash or discard them: no toast.
        case blocked
        case failed(String)
        /// The user cancelled (e.g. the account sheet of a fetch): no toast.
        case cancelled
    }

    /// Checks `target` out for a click in the sidebar, Branches, History or a
    /// pull request. When git refuses because local changes are in the way,
    /// it publishes `blockedCheckout` instead of failing. Operations that
    /// check out as one step of something else (a rebase by drop) call
    /// `checkoutBranch(_:)` and get git's refusal as an error.
    func checkout(_ target: CheckoutTarget) async -> CheckoutOutcome {
        let result: Result<Void, Error>
        switch target {
        case .branch(let ref):
            result = await checkoutBranch(ref)
        case .commit(let sha):
            result = await checkoutCommit(sha)
        case .pullRequestBranch(let name):
            result = await runRefMutation {
                try await ensureCheckedOut(branch: name)
                await refreshAfterRefMutation(reloadLog: true)
            } onFailure: {
                await loadRefs()
            }
        }
        return await outcome(of: result, target: target)
    }

    /// `checkoutPullRequestBranch()` for the pull request detail: fetches,
    /// then checks the selected pull request's branch out, asking about
    /// local changes in the way like `checkout(_:)`.
    func checkoutSelectedPullRequest() async -> CheckoutOutcome {
        let target = CheckoutTarget.pullRequestBranch(pullRequests.selected?.sourceBranch ?? "")
        let result = await checkoutPullRequestBranch().map { _ in () }
        return await outcome(of: result, target: target)
    }

    /// Stashes the files a refused checkout pointed at — only those, staged
    /// and unstaged changes alike, untracked ones included — then checks the
    /// same target out again. The other changes stay and come along, as git
    /// carries them.
    func stashBlockingChangesAndCheckout(_ blocked: BlockedCheckout) async -> CheckoutOutcome {
        guard !isMutating else { return .failed(GitError.busy.userMessage) }
        blockedCheckout = nil
        isMutating = true
        do {
            try await cli.stashPush(message: blocked.stashMessage,
                                    includeUntracked: blocked.files.contains(where: \.isUntracked),
                                    paths: blocked.files.flatMap(\.allPaths))
        } catch {
            isMutating = false
            await workingCopy.refreshStatus()
            return .failed(error.userMessage)
        }
        isMutating = false
        let stashed = String(localized: "Your changes are in Stashes.")
        switch await checkout(blocked.target) {
        case .done(let message):
            return .done("\(message). \(stashed)")
        case .failed(let message):
            // Only a successful checkout reloads the log, which draws the
            // new stash in the graph.
            await refreshAfterRefMutation(reloadLog: false)
            return .failed("\(message) \(stashed)")
        case let other:
            return other
        }
    }

    /// Discards the files a refused checkout pointed at, then checks the same
    /// target out again. Untracked files go to the Trash, like the staging
    /// Discard. Changes that weren't in the way stay and come along, as git
    /// carries them.
    func discardBlockingChangesAndCheckout(_ blocked: BlockedCheckout) async -> CheckoutOutcome {
        guard !isMutating else { return .failed(GitError.busy.userMessage) }
        blockedCheckout = nil
        let tracked = blocked.files.filter { !$0.isUntracked }
        let untracked = blocked.files.filter(\.isUntracked)
        isMutating = true
        do {
            try await cli.restoreFromHead(paths: tracked.flatMap(\.allPaths))
            try await cli.deleteUntracked(paths: untracked.map(\.path))
        } catch {
            isMutating = false
            await workingCopy.refreshStatus()
            return .failed(error.userMessage)
        }
        isMutating = false
        return await checkout(blocked.target)
    }

    private func outcome(of result: Result<Void, Error>, target: CheckoutTarget) async -> CheckoutOutcome {
        switch result {
        case .success:
            return .done(target.successMessage)
        case .failure(let error) where error is CancellationError:
            return .cancelled
        case .failure(let error):
            guard let blocked = await blockedCheckout(for: error, target: target) else {
                return .failed(error.userMessage)
            }
            blockedCheckout = blocked
            return .blocked
        }
    }

    /// The question to ask when `error` is git refusing to check out over
    /// local changes, built from a fresh status: the files git named. `nil`
    /// when it's another failure or none of those files shows up.
    private func blockedCheckout(for error: Error, target: CheckoutTarget) async -> BlockedCheckout? {
        guard case .paths(let paths)? = BlockingLocalChanges(error: error) else { return nil }
        await workingCopy.refreshStatus()
        let named = Set(paths)
        let files = workingCopy.status.files.filter { $0.allPaths.contains(where: named.contains) }
        guard !files.isEmpty else { return nil }
        return BlockedCheckout(files: files, target: target)
    }
}
