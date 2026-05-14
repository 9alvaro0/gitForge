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

    func fetch() async {
        // `autoFetchInFlight` covers the silent auto-fetcher path — without
        // it the user clicking Fetch while the timer-driven fetch was in
        // flight would fire a second `git fetch` subprocess in parallel.
        guard remoteOperation == nil, !autoFetchInFlight else { return }
        remoteOperation = .fetching
        remoteFailure = nil
        defer { remoteOperation = nil }
        do {
            try await cli.fetchAll()
            lastFetchedAt = .now
            await loadRefs()
        } catch {
            remoteFailure = RemoteFailure.from(error)
            // A partial fetch may have updated some remote refs before
            // failing. Reload so the UI doesn't keep showing pre-fetch
            // counters until the next 30s poller tick.
            await loadRefs()
        }
    }

    func pull(rebase: Bool = false, ffOnly: Bool = false) async {
        guard remoteOperation == nil else { return }
        remoteOperation = .pulling
        remoteFailure = nil
        defer { remoteOperation = nil }
        do {
            try await cli.pull(rebase: rebase, ffOnly: ffOnly)
            await loadRefs()
            await refreshStatus()
            await reloadLog()
        } catch {
            remoteFailure = RemoteFailure.from(error)
            // A failed pull may have left a merge in progress (MERGE_HEAD).
            // Refresh the integration cluster so the Conflicts view paints
            // the unmerged paths immediately, instead of waiting on the
            // next watcher tick.
            await refreshAfterIntegration()
        }
    }

    func push(forceWithLease: Bool = false) async {
        guard remoteOperation == nil else { return }
        remoteOperation = .pushing
        remoteFailure = nil
        defer { remoteOperation = nil }
        let setUpstream = upstream == nil
        // Resolve the configured remote for the current branch so users with
        // a renamed `origin` (upstream/fork patterns) push to the right place.
        // Falls back to "origin" for first push (no tracking config yet) and
        // when config read fails.
        let resolvedRemote: String = await {
            guard let branch = currentBranchName else { return "origin" }
            return await cli.upstreamRemoteName(forBranch: branch) ?? "origin"
        }()
        // Force-with-lease compares against the local remote-tracking ref. If
        // the user never fetched, that ref can be days old and the "safe
        // force" silently pisas commits a collaborator pushed in the
        // meantime. Refresh the remote ref first so the lease has real teeth.
        // We fail silently on the fetch — git will reject the push if
        // anything's wrong with the remote anyway.
        if forceWithLease {
            try? await cli.fetch(remote: resolvedRemote)
            await loadRefs()
        }
        do {
            try await cli.push(
                setUpstream: setUpstream,
                remote: resolvedRemote,
                branch: currentBranchName,
                forceWithLease: forceWithLease
            )
            if setUpstream { upstream = await cli.upstreamName() }
            // `loadRefs()` already calls `loadAheadBehind()` at its tail,
            // so a separate call here would just duplicate the rev-list.
            await loadRefs()
        } catch {
            remoteFailure = RemoteFailure.from(error)
            // Push can partially succeed (pack uploaded but ref update
            // rejected, or N of M refs accepted). Reload so aheadCount and
            // remote-tracking refs reflect what really landed.
            await loadRefs()
        }
    }
}
