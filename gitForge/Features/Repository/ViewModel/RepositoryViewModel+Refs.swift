import Foundation

extension RepositoryViewModel {
    func loadRefs() async {
        async let refsTask: [GitRef]? = try? cli.refs()
        async let currentTask: String? = cli.currentBranchName()
        async let stashTask: [Stash]? = try? cli.stashes()
        async let unmergedTask: [String]? = try? cli.unmergedLocalBranches()
        var refsChanged = false
        if let refs = await refsTask {
            self.refs = refs
            refsChanged = true
        }
        if let current = await currentTask {
            self.currentBranchName = current
        }
        if let stashes = await stashTask {
            self.stashes = stashes
        }
        if let unmerged = await unmergedTask {
            self.unmergedLocalBranchRefs = unmerged
        }
        // Refs feed into the graph layout (priority lanes — main/develop/
        // release/* pin to the leftmost columns). When loadInitial and
        // loadRefs run concurrently the first recomputeGraph fires with an
        // empty refs dictionary and priority loses, so re-run once refs
        // actually land.
        if refsChanged && !commits.isEmpty {
            recomputeGraph()
        }
        await loadAheadBehind()
    }
}
