import Foundation
import os

extension RepositoryViewModel {
    /// Open the detail view for a PR/MR — clears any prior detail state and
    /// kicks off a parallel fetch of detail / commits / files.
    ///
    /// Bumps `pullRequestDetailGen` so an in-flight fetch from a previous
    /// selection drops its write-back when it resumes — fixes the
    /// "rapid-click PR#1 → PR#2 paints PR#1's data into PR#2's pane" race.
    func selectPullRequest(_ pr: PullRequest) {
        pullRequestDetailGen &+= 1
        selectedPullRequest = pr
        pullRequestDetail = nil
        pullRequestCommits = []
        pullRequestFiles = []
        pullRequestDetailError = nil
        Task { await loadPullRequestDetail() }
    }

    /// Close the detail view and clear cached data.
    func closePullRequestDetail() {
        pullRequestDetailGen &+= 1
        selectedPullRequest = nil
        pullRequestDetail = nil
        pullRequestCommits = []
        pullRequestFiles = []
        pullRequestDetailError = nil
    }

    /// Fetch the three detail payloads in parallel. Errors are collected into
    /// `pullRequestDetailError` (any one failure surfaces an error state).
    ///
    /// Each post-await write is gated on `pullRequestDetailGen` so a fresh
    /// `selectPullRequest` / `closePullRequestDetail` invalidates this loader
    /// — previously the `!pullRequestDetailLoading` guard rebounded the new
    /// selection's load entirely, leaving the user staring at the old PR's
    /// data under a new selection.
    func loadPullRequestDetail() async {
        pullRequestDetailGen &+= 1
        let gen = pullRequestDetailGen
        guard let pr = selectedPullRequest, let host = pullRequestsHost else { return }
        guard let token = RemoteCredentialsStore.shared.token(for: host.host) else {
            pullRequestDetailError = "No token configured for \(host.host)."
            return
        }

        pullRequestDetailLoading = true
        pullRequestDetailError = nil
        defer { if gen == pullRequestDetailGen { pullRequestDetailLoading = false } }

        let provider = PullRequestProviderFactory.make(for: host)
        let number = pr.number

        async let detail = Self.safeFetch { try await provider.fetchDetail(host: host, number: number, token: token) }
        async let commits = Self.safeFetch { try await provider.fetchCommits(host: host, number: number, token: token) }
        async let files = Self.safeFetch { try await provider.fetchFiles(host: host, number: number, token: token) }

        let detailResult = await detail
        let commitsResult = await commits
        let filesResult = await files

        guard gen == pullRequestDetailGen else { return }

        switch detailResult {
        case .success(let value): pullRequestDetail = value
        case .failure(let error): pullRequestDetailError = Self.message(for: error)
        }
        switch commitsResult {
        case .success(let value): pullRequestCommits = value
        case .failure(let error):
            if pullRequestDetailError == nil {
                pullRequestDetailError = Self.message(for: error)
            }
        }
        switch filesResult {
        case .success(let value): pullRequestFiles = value
        case .failure(let error):
            if pullRequestDetailError == nil {
                pullRequestDetailError = Self.message(for: error)
            }
        }
    }

    private static func safeFetch<T: Sendable>(_ block: @Sendable () async throws -> T) async -> Result<T, Error> {
        do { return .success(try await block()) }
        catch { return .failure(error) }
    }

    /// Try to integrate `pr.targetBranch` into `pr.sourceBranch` locally so the
    /// user can resolve any merge conflicts in the existing Conflicts view.
    ///
    /// Steps: refuse if a merge/rebase is already in progress or the working
    /// tree is dirty → fetch → checkout (or create-and-checkout) the source
    /// branch → `git merge <remote>/<targetBranch>`. Conflicts surface as
    /// `.conflicts`; the caller is expected to route to the conflicts section.
    func attemptLocalMergeForPullRequest() async -> IntegrationOutcome {
        guard let pr = selectedPullRequest else {
            return .failed("No pull request selected.")
        }
        guard !pullRequestLocalMergeRunning else {
            return .failed("A local merge is already running.")
        }
        if mergeState.isInProgress {
            return .failed("A merge or rebase is already in progress. Resolve it from the Conflicts section first.")
        }
        if !status.isClean {
            return .failed("Working tree has uncommitted changes. Commit, stash or discard them before integrating.")
        }

        pullRequestLocalMergeRunning = true
        defer { pullRequestLocalMergeRunning = false }

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
            if mergeState.isInProgress || !conflictFiles.isEmpty {
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

    private static func message(for error: Error) -> String {
        if let typed = error as? PullRequestFetchError {
            return typed.errorDescription ?? "Request failed"
        }
        return error.localizedDescription
    }

    /// Refresh the PR/MR list for the active repository. Resolution order:
    /// 1) detect remote host (`origin`); skip if not GitHub/GitLab
    /// 2) read token from Keychain; surface "needs token" if missing
    /// 3) hit provider, store results / error
    func loadPullRequests(force: Bool = false) async {
        guard !pullRequestsLoading else { return }

        // Throttle: don't re-hit the API more than once every 30s unless forced.
        if !force, let last = pullRequestsLastLoadedAt,
           Date().timeIntervalSince(last) < 30 {
            return
        }

        pullRequestsLoading = true
        pullRequestsError = nil
        defer { pullRequestsLoading = false }

        guard let host = await cli.remoteHost() else {
            pullRequestsHost = nil
            pullRequests = []
            pullRequestsRequiresToken = false
            pullRequestsError = nil
            return
        }
        pullRequestsHost = host
        Self.logger.info("Pulls: detected host \(host.host, privacy: .public) (\(host.provider.rawValue, privacy: .public))")

        guard let token = RemoteCredentialsStore.shared.token(for: host.host) else {
            pullRequests = []
            pullRequestsRequiresToken = true
            Self.logger.info("Pulls: no token for host \(host.host, privacy: .public)")
            return
        }
        pullRequestsRequiresToken = false

        let provider = PullRequestProviderFactory.make(for: host)
        do {
            let results = try await provider.fetchOpen(host: host, token: token)
            pullRequests = results
            pullRequestsLastLoadedAt = .now
        } catch let error as PullRequestFetchError {
            pullRequestsError = error.errorDescription
        } catch {
            pullRequestsError = error.localizedDescription
        }
    }
}
