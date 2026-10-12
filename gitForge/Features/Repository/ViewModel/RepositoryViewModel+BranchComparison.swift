import Foundation

extension RepositoryViewModel {
    /// What the Branches inspector compares other branches with: local
    /// `main`, else `master`; nil when there's neither.
    var trunkBranch: GitRef? {
        localBranches.first { $0.name == "main" } ?? localBranches.first { $0.name == "master" }
    }

    /// `ref` against the trunk. Nil for tags, for the trunk itself, without a
    /// trunk, or when git fails (the inspector just leaves the section out).
    func comparison(of ref: GitRef) async -> BranchComparison? {
        guard !ref.isTag, let trunk = trunkBranch, trunk.id != ref.id else { return nil }
        do {
            async let counts = cli.aheadBehind(branch: ref.fullRefName, upstream: trunk.fullRefName)
            async let commits = cli.log(limit: BranchComparison.commitLimit,
                                        refs: ["\(trunk.fullRefName)..\(ref.fullRefName)"])
            let (c, list) = try await (counts, commits)
            return BranchComparison(trunk: trunk.name, ahead: c.ahead, behind: c.behind, commitsNotInTrunk: list)
        } catch {
            return nil
        }
    }

    /// Pushes a local branch, checked out or not. The current branch goes
    /// through `push()`; another branch is pushed to the remote git would
    /// pick for it, setting its upstream when it has none. Same return
    /// contract as `push()`: failures land in `remoteFailure`.
    @discardableResult
    func pushBranch(_ ref: GitRef) async -> Bool {
        guard ref.isLocalBranch else { return false }
        if ref.name == currentBranchName { return await push() }
        guard remoteOperation == nil else { return false }
        remoteOperation = .pushing
        remoteFailure = nil
        defer { remoteOperation = nil }
        let remote = await cli.pushRemoteName(forBranch: ref.name) ?? "origin"
        do {
            try await cli.pushBranch(ref.name, remote: remote, setUpstream: ref.upstream == nil)
            await loadRefs()
            return true
        } catch {
            remoteFailure = RemoteFailure.from(error)
            await loadRefs()
            return false
        }
    }
}
