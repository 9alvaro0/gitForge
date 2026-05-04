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

    func pull() async {
        guard remoteOperation == nil else { return }
        remoteOperation = .pulling
        defer { remoteOperation = nil }
        do {
            try await cli.pull()
            resetLog()
            await loadInitial()
            await loadRefs()
            await refreshStatus()
        } catch {
            remoteFailure = RemoteFailure.from(error)
        }
    }

    func push() async {
        guard remoteOperation == nil else { return }
        remoteOperation = .pushing
        defer { remoteOperation = nil }
        let setUpstream = upstream == nil
        do {
            try await cli.push(setUpstream: setUpstream, branch: currentBranchName)
            if setUpstream { upstream = await cli.upstreamName() }
            await loadRefs()
        } catch {
            remoteFailure = RemoteFailure.from(error)
        }
    }
}
