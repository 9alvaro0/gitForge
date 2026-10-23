import Foundation

extension RepositoryViewModel {
    /// Reads refs / remote HEADs / current branch / stashes / unmerged-branch
    /// refs in parallel and applies them atomically. Two overlapping calls
    /// (watcher tick + manual refresh, etc.) share the same `refsGen` token:
    /// the older one drops all its writes if the token moved while it was
    /// awaiting.
    func loadRefs() async {
        refsGen &+= 1
        let gen = refsGen
        async let refsTask: [GitRef]? = try? cli.refs()
        async let remoteHeadsTask: [String: String]? = try? cli.remoteHeads()
        async let currentTask: HeadBranch? = try? cli.headBranch()
        async let stashTask: [Stash]? = try? cli.stashes()
        async let unmergedTask: [String]? = try? cli.unmergedLocalBranches()
        async let headTask: String? = cli.headSha()

        let refsResult = await refsTask
        let remoteHeadsResult = await remoteHeadsTask
        let currentResult = await currentTask
        let stashResult = await stashTask
        let unmergedResult = await unmergedTask
        let headResult = await headTask

        guard gen == refsGen else { return }

        // Compared with what is in place before it is overwritten: the graph only
        // needs laying out again when what it reads differs. The same refs are
        // not written, so they keep their storage and everything that compares
        // them later (the chips, the refs' own didSet) does so in O(1).
        var graphInputChanged = false
        if let refs = refsResult, refs != self.refs {
            graphInputChanged = true
            self.refs = refs
        }
        // They pick the remote trunk the graph draws.
        if let remoteHeads = remoteHeadsResult, remoteHeads != self.remoteHeads {
            graphInputChanged = true
            self.remoteHeads = remoteHeads
        }
        // A detached HEAD clears the name; only a failed read keeps it.
        if let current = currentResult {
            self.currentBranchName = current.name
        }
        if let stashes = stashResult {
            self.stashes = stashes
        }
        if let unmerged = unmergedResult {
            self.unmergedLocalBranchRefs = unmerged
        }
        // nil here means an empty repo (a failed read looks the same), so it's
        // always written.
        if headResult != self.headSha {
            graphInputChanged = true
            self.headSha = headResult
        }
        // Refs, remote HEADs and HEAD feed into the graph layout (line names,
        // HEAD, the trunks' columns and colours). Recompute when one changed,
        // even before the first log is published: a page still being laid out
        // with the old ones sees the change and lays itself out again once
        // published. When all are as they were, the graph already describes
        // them: laying out the whole log again would only cost a pass (and a
        // second one for a reload in flight). The recompute keeps the stashes
        // the loaded log was fetched with, so a stash dropped here stays drawn
        // as a stash until the log reloads.
        if graphInputChanged {
            await history.recomputeGraph()
        }
        await loadAheadBehind()
    }

    /// Reloads the log when the refs now ask for remote branches it wasn't
    /// fetched with (`HistoryStore.isScopeStale`): after a fetch, a push, a
    /// refresh or a branch change moved one, or when a repo opens. The refs
    /// must be read first. The user didn't ask for it, often a background
    /// fetch did, so it keeps the pages already loaded and the selection on
    /// them (`reloadLog(keepingDepth:)`).
    func reloadLogIfScopeMoved() async {
        guard history.isScopeStale else { return }
        await history.reloadLog(keepingDepth: true)
    }
}
