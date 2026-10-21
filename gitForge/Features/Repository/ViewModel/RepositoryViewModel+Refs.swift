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
        // Refs feed into the graph layout (line names, HEAD, the trunks'
        // columns and colours). Recompute even before the first log is
        // published: a page still being laid out with the old refs sees the
        // change and lays itself out again once published. The recompute
        // keeps the stashes the loaded log was fetched with, so a stash
        // dropped here stays drawn as a stash until the log reloads.
        if refsChanged {
            await history.recomputeGraph()
        }
        await loadAheadBehind()
    }
}
