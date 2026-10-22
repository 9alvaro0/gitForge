import Foundation

extension RepositoryViewModel {
    /// Reads the upstream tracking ref and the `ahead/behind` counts. Two
    /// overlapping calls share `aheadBehindGen`: the older one drops its
    /// writes if the token moved while it was awaiting, so a slow watcher
    /// tick can't stomp a fresher manual fetch's pill.
    func loadAheadBehind() async {
        aheadBehindGen &+= 1
        let gen = aheadBehindGen
        let resolvedUpstream = await cli.upstreamName()
        guard gen == aheadBehindGen else { return }
        upstream = resolvedUpstream
        guard let resolvedUpstream, let branch = currentBranchName else {
            aheadCount = 0
            behindCount = 0
            return
        }
        do {
            let counts = try await cli.aheadBehind(branch: branch, upstream: resolvedUpstream)
            guard gen == aheadBehindGen else { return }
            aheadCount = counts.ahead
            behindCount = counts.behind
        } catch {
            guard gen == aheadBehindGen else { return }
            aheadCount = 0
            behindCount = 0
        }
    }

    /// Returns `true` only when the fetch ran and succeeded — `false` when it
    /// was refused (another operation in flight) or failed. Callers use it
    /// to decide whether a success toast is truthful.
    @discardableResult
    func fetch() async -> Bool {
        // `autoFetchInFlight` covers the silent auto-fetcher path — without
        // it the user clicking Fetch while the timer-driven fetch was in
        // flight would fire a second `git fetch` subprocess in parallel.
        guard remoteOperation == nil, !autoFetchInFlight else { return false }
        remoteOperation = .fetching
        remoteFailure = nil
        defer { remoteOperation = nil }
        do {
            try await cli.fetchAll()
            lastFetchedAt = .now
            await loadRefs()
            // What a pull would bring shows up as ghosts in the graph.
            await reloadLogIfScopeMoved()
            operationSuccess = .fetch(upstream: upstream, behind: behindCount)
            return true
        } catch {
            remoteFailure = RemoteFailure.from(error)
            // A partial fetch may have updated some remote refs before
            // failing. Reload so the UI doesn't keep showing pre-fetch
            // counters (or graph) until the next 30s poller tick.
            await loadRefs()
            await reloadLogIfScopeMoved()
            return false
        }
    }

    /// Pull rewrites the index and worktree, so unlike fetch/push it's also
    /// a local mutation: it holds `isMutating` (which suspends the watcher)
    /// so a commit or discard can't race it for `.git/index.lock`. `GitCLI`
    /// being an actor doesn't serialise commands — `run` suspends while the
    /// subprocess runs, so calls interleave.
    /// Same return contract as `fetch()`.
    @discardableResult
    func pull(rebase: Bool = false, ffOnly: Bool = false) async -> Bool {
        guard remoteOperation == nil, !isMutating else { return false }
        remoteOperation = .pulling
        isMutating = true
        remoteFailure = nil
        defer {
            remoteOperation = nil
            isMutating = false
        }
        let headBefore = await cli.headSha()
        do {
            try await cli.pull(rebase: rebase, ffOnly: ffOnly)
            await loadRefs()
            await workingCopy.refreshStatus()
            await history.reloadLog()
            let headAfter = await cli.headSha()
            operationSuccess = .pull(upstream: upstream, changed: headBefore != headAfter)
            return true
        } catch {
            // A failed pull may have left a merge in progress (MERGE_HEAD).
            // Refresh the integration cluster so the Conflicts view paints
            // the unmerged paths immediately, instead of waiting on the
            // next watcher tick. The fresh status also names the files a
            // refusal over local changes points at.
            await refreshAfterIntegration()
            if let request = discardRequest(for: error, rebase: rebase, ffOnly: ffOnly) {
                pullDiscardRequest = request
            } else {
                remoteFailure = RemoteFailure.from(error)
            }
            return false
        }
    }

    /// Discards the files a refused pull pointed at, then runs that pull
    /// again. Untracked files go to the Trash, like the staging Discard.
    /// Same return contract as `fetch()`.
    @discardableResult
    func discardBlockingChangesAndPull(_ request: PullDiscardRequest) async -> Bool {
        guard remoteOperation == nil, !isMutating else { return false }
        pullDiscardRequest = nil
        let tracked = request.files.filter { !$0.isUntracked }
        let untracked = request.files.filter(\.isUntracked)
        isMutating = true
        do {
            try await cli.restoreFromHead(paths: tracked.flatMap(\.allPaths))
            try await cli.deleteUntracked(paths: untracked.map(\.path))
        } catch {
            isMutating = false
            remoteFailure = .other(error.userMessage)
            await workingCopy.refreshStatus()
            return false
        }
        isMutating = false
        return await pull(rebase: request.rebase, ffOnly: request.ffOnly)
    }

    /// The question to ask when `error` is git refusing to pull over local
    /// changes, built from the current status: the files git named, or for
    /// a rebase every tracked change. `nil` when it's another failure or
    /// none of those files shows up in the status.
    private func discardRequest(for error: Error, rebase: Bool, ffOnly: Bool) -> PullDiscardRequest? {
        guard let blocking = BlockingLocalChanges(error: error) else { return nil }
        let changed = workingCopy.status.files
        let files: [WorkingCopyFile]
        switch blocking {
        case .paths(let paths):
            let named = Set(paths)
            files = changed.filter { $0.allPaths.contains(where: named.contains) }
        case .allTrackedChanges:
            files = changed.filter { !$0.isUntracked }
        }
        guard !files.isEmpty else { return nil }
        return PullDiscardRequest(files: files, refusedByRebase: blocking == .allTrackedChanges,
                                  rebase: rebase, ffOnly: ffOnly)
    }

    /// Same return contract as `fetch()`.
    @discardableResult
    func push(forceWithLease: Bool = false) async -> Bool {
        guard remoteOperation == nil else { return false }
        remoteOperation = .pushing
        remoteFailure = nil
        defer { remoteOperation = nil }
        let setUpstream = upstream == nil
        let branch = currentBranchName
        // The remote git pushes this branch to (pushRemote, pushDefault, then
        // the tracking remote), so fork / triangular setups push — and are
        // signed — where git would. "origin" when nothing is configured.
        let resolvedRemote: String = await {
            guard let branch = currentBranchName else { return "origin" }
            return await cli.pushRemoteName(forBranch: branch) ?? "origin"
        }()
        // Force-with-lease compares against the local remote-tracking ref. If
        // the user never fetched, that ref can be days old and the "safe
        // force" silently overwrites commits a collaborator pushed in the
        // meantime. Refresh the remote ref first so the lease has real teeth.
        // We fail silently on the fetch — git will reject the push if
        // anything's wrong with the remote anyway.
        if forceWithLease {
            do {
                try await cli.fetch(remote: resolvedRemote)
            } catch is CancellationError {
                // "Choose an account" → Cancel: stop here, don't ask again for the push.
                remoteFailure = .cancelled
                return false
            } catch {}
            await loadRefs()
        }
        // Read after the lease fetch so the count matches what this push sends.
        let pushedCount = aheadCount
        do {
            try await cli.push(
                setUpstream: setUpstream,
                remote: resolvedRemote,
                branch: branch,
                forceWithLease: forceWithLease
            )
            if setUpstream { upstream = await cli.upstreamName() }
            // `loadRefs()` already calls `loadAheadBehind()` at its tail,
            // so a separate call here would just duplicate the rev-list.
            await loadRefs()
            // The lease fetch or the push itself may have moved a remote
            // branch the graph loads.
            await reloadLogIfScopeMoved()
            operationSuccess = .push(branch: branch, remote: resolvedRemote, ahead: pushedCount,
                                     firstPush: setUpstream, forced: forceWithLease)
            return true
        } catch {
            remoteFailure = RemoteFailure.from(error)
            // Push can partially succeed (pack uploaded but ref update
            // rejected, or N of M refs accepted). Reload so aheadCount and
            // remote-tracking refs reflect what really landed.
            await loadRefs()
            await reloadLogIfScopeMoved()
            return false
        }
    }
}
