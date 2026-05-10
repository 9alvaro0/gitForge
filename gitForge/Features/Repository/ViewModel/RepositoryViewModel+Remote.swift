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
        guard remoteOperation == nil else { return }
        remoteOperation = .fetching
        remoteFailure = nil
        defer { remoteOperation = nil }
        do {
            try await cli.fetchAll()
            lastFetchedAt = .now
            await loadRefs()
        } catch {
            remoteFailure = RemoteFailure.from(error)
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
        do {
            try await cli.push(
                setUpstream: setUpstream,
                branch: currentBranchName,
                forceWithLease: forceWithLease
            )
            if setUpstream { upstream = await cli.upstreamName() }
            // `loadRefs()` already calls `loadAheadBehind()` at its tail,
            // so a separate call here would just duplicate the rev-list.
            await loadRefs()
        } catch {
            remoteFailure = RemoteFailure.from(error)
        }
    }
}
