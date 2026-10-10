import Foundation

extension RepositoryViewModel {
    /// Reads refs / current branch / stashes / unmerged-branch refs in parallel
    /// and applies them atomically. Two overlapping calls (watcher tick + manual
    /// refresh, etc.) share the same `refsGen` token: the older one drops all
    /// its writes if the token moved while it was awaiting.
    func loadRefs() async {
        refsGen &+= 1
        let gen = refsGen
        async let refsTask: [GitRef]? = try? cli.refs()
        async let currentTask: String? = cli.currentBranchName()
        async let stashTask: [Stash]? = try? cli.stashes()
        async let unmergedTask: [String]? = try? cli.unmergedLocalBranches()
        async let headTask: String? = cli.headSha()

        let refsResult = await refsTask
        let currentResult = await currentTask
        let stashResult = await stashTask
        let unmergedResult = await unmergedTask
        let headResult = await headTask

        guard gen == refsGen else { return }

        var refsChanged = false
        if let refs = refsResult {
            self.refs = refs
            refsChanged = true
        }
        if let current = currentResult {
            self.currentBranchName = current
        }
        if let stashes = stashResult {
            self.stashes = stashes
        }
        if let unmerged = unmergedResult {
            self.unmergedLocalBranchRefs = unmerged
        }
        // Unlike the branch name, nil here is meaningful (empty repo), so it's
        // always written.
        self.headSha = headResult
        // Refs feed into the graph layout (priority lanes — main/develop/
        // release/* pin to the leftmost columns). When loadInitial and
        // loadRefs run concurrently the first recomputeGraph fires with an
        // empty refs dictionary and priority loses, so re-run once refs
        // actually land.
        if refsChanged && !commits.isEmpty {
            await recomputeGraph()
        }
        await loadAheadBehind()
    }
}
