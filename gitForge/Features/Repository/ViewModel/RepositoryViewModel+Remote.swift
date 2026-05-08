import Foundation

extension RepositoryViewModel {
    func loadAheadBehind() async {
        upstream = await cli.upstreamName()
        guard let upstream, let branch = currentBranchName else {
            aheadCount = 0
            behindCount = 0
            return
        }
        do {
            let counts = try await cli.aheadBehind(branch: branch, upstream: upstream)
            aheadCount = counts.ahead
            behindCount = counts.behind
        } catch {
            aheadCount = 0
            behindCount = 0
        }
    }

    func fetch() async {
        guard remoteOperation == nil else { return }
        remoteOperation = .fetching
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
        defer { remoteOperation = nil }
        do {
            try await cli.pull(rebase: rebase, ffOnly: ffOnly)
            await loadRefs()
            await refreshStatus()
            await reloadLog()
        } catch {
            remoteFailure = RemoteFailure.from(error)
        }
    }

    func push(forceWithLease: Bool = false) async {
        guard remoteOperation == nil else { return }
        remoteOperation = .pushing
        defer { remoteOperation = nil }
        let setUpstream = upstream == nil
        do {
            try await cli.push(
                setUpstream: setUpstream,
                branch: currentBranchName,
                forceWithLease: forceWithLease
            )
            if setUpstream { upstream = await cli.upstreamName() }
            await loadRefs()
            await loadAheadBehind()
        } catch {
            remoteFailure = RemoteFailure.from(error)
        }
    }
}
