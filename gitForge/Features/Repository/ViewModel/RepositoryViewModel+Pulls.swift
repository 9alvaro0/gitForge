import Foundation

/// Local integration of the selected pull request. The PR list and detail
/// live in `PullRequestStore`; this stays here because it checks out,
/// merges and refreshes the whole session (refs, status, conflicts).
extension RepositoryViewModel {
    /// Try to integrate `pr.targetBranch` into `pr.sourceBranch` locally so the
    /// user can resolve any merge conflicts in the existing Conflicts view.
    ///
    /// Steps: refuse if a merge/rebase is already in progress or the working
    /// tree is dirty → fetch → checkout (or create-and-checkout) the source
    /// branch → `git merge <remote>/<targetBranch>`. Conflicts surface as
    /// `.conflicts`; the caller is expected to route to the conflicts section.
    func attemptLocalMergeForPullRequest() async -> IntegrationOutcome {
        guard let pr = pullRequests.selected else {
            return .failed("No pull request selected.")
        }
        guard !pullRequests.localMergeRunning else {
            return .failed("A local merge is already running.")
        }
        if mergeState.isInProgress {
            return .failed("A merge or rebase is already in progress. Resolve it from the Conflicts section first.")
        }
        if !status.isClean {
            return .failed("Working tree has uncommitted changes. Commit, stash or discard them before integrating.")
        }

        pullRequests.localMergeRunning = true
        defer { pullRequests.localMergeRunning = false }

        do {
            try await cli.fetchAll()
            lastFetchedAt = .now
            await loadRefs()
        } catch {
            let message = error.userMessage
            return .failed("Fetch failed: \(message)")
        }

        // Pick the freshly fetched ref to merge in. Prefer a remote-tracking
        // branch (so we use the latest tip) and fall back to a local branch
        // with the same name when no matching remote ref exists.
        guard let targetSpec = mergeRefSpec(for: pr.targetBranch) else {
            return .failed("Couldn't find branch \"\(pr.targetBranch)\" locally or on any remote.")
        }

        // Make sure the source branch is checked out — create it tracking the
        // remote tip if it doesn't exist locally yet.
        do {
            try await ensureCheckedOut(branch: pr.sourceBranch)
            await refreshAfterRefMutation(reloadLog: true)
        } catch {
            let message = error.userMessage
            return .failed("Couldn't check out \(pr.sourceBranch): \(message)")
        }

        do {
            try await cli.merge(branch: targetSpec)
            await refreshAfterIntegration()
            return .clean
        } catch {
            // Mirror `+Operations`: parallel conflicts+status+refs+reloadLog
            // in both branches. Without `loadRefs` in the catch, a merge that
            // mutated refs before failing on a hook would leave the sidebar
            // chips stale.
            await refreshAfterIntegration()
            if mergeState.isInProgress || !conflicts.files.isEmpty {
                return .conflicts
            }
            let message = error.userMessage
            return .failed(message)
        }
    }

    /// Resolves a branch name to the merge spec we should pass to `git merge`.
    /// Prefers `origin/<branch>` then any other remote, then a local branch.
    /// Returns nil when no matching ref exists.
    private func mergeRefSpec(for branchName: String) -> String? {
        let originRef = refs.first { ref in
            if case .remoteBranch(let remote) = ref.kind, remote == "origin" {
                return ref.displayName == branchName
            }
            return false
        }
        if let originRef { return originRef.name }

        let anyRemoteRef = refs.first { ref in
            ref.isRemoteBranch && ref.displayName == branchName
        }
        if let anyRemoteRef { return anyRemoteRef.name }

        let localRef = refs.first { $0.isLocalBranch && $0.name == branchName }
        return localRef?.name
    }

    /// Checkout `branch`, creating it from a matching remote tip if it doesn't
    /// exist locally. No-op when it's already the current branch.
    private func ensureCheckedOut(branch: String) async throws {
        if currentBranchName == branch { return }
        let hasLocal = refs.contains { $0.isLocalBranch && $0.name == branch }
        if hasLocal {
            try await cli.checkout(branch: branch)
            return
        }
        let remoteRef = refs.first { ref in
            ref.isRemoteBranch && ref.displayName == branch
        }
        guard let remoteRef else {
            throw GitError.commandFailed(
                args: ["checkout", branch],
                exitCode: 1,
                stderr: "Branch \"\(branch)\" doesn't exist locally and no remote tracks it."
            )
        }
        try await cli.createBranch(branch, startingAt: remoteRef.name, checkout: true)
    }
}
