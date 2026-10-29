import Foundation

/// What a log's `git log` walks (§3.1). A log keeps the scope its first page was fetched
/// with and fetches every later page with it too, so remote branches go in by sha: a fetch
/// that moves one between two pages can't change the walk under `--skip`.
nonisolated struct HistoryScope: Sendable, Equatable {
    /// `git log` revisions: HEAD, local branches not merged into HEAD, the tips of the
    /// remote branches in scope (by sha, each once, in the order of their names), `--tags`,
    /// then the stashes.
    let revisions: [String]
    let stashShas: Set<String>
    /// Remote branches in scope, name → tip sha when the scope was made.
    let remoteTips: [String: String]
    let includesAllRemotes: Bool

    /// HEAD goes first. Local branches merged into HEAD ride along via its ancestry. A
    /// remote branch is in scope when a local branch is behind it (it is that branch's
    /// upstream, not gone) or it stands in for a missing trunk (`remoteTrunks`); with
    /// `includesAllRemotes`, every remote branch is.
    static func make(refs: [GitRef], unmergedLocalBranchRefs: [String], stashes: [Stash],
                     remoteTrunks: [String: Int], includesAllRemotes: Bool) -> HistoryScope {
        let remotes = Dictionary(refs.filter(\.isRemoteBranch).map { ($0.name, $0.targetSha) },
                                 uniquingKeysWith: { first, _ in first })
        let remoteTips: [String: String]
        if includesAllRemotes {
            remoteTips = remotes
        } else {
            var wanted = Set(remoteTrunks.keys)
            for ref in refs where ref.isLocalBranch && (ref.behind ?? 0) > 0 && !ref.upstreamGone {
                if let upstream = ref.upstream { wanted.insert(upstream) }
            }
            remoteTips = remotes.filter { wanted.contains($0.key) }
        }

        var seen: Set<String> = []
        let remoteShas = remoteTips.keys.sorted().compactMap { name -> String? in
            guard let sha = remoteTips[name], seen.insert(sha).inserted else { return nil }
            return sha
        }
        let stashShas = stashes.map(\.sha)
        return HistoryScope(revisions: ["HEAD"] + unmergedLocalBranchRefs + remoteShas + ["--tags"] + stashShas,
                            stashShas: Set(stashShas),
                            remoteTips: remoteTips,
                            includesAllRemotes: includesAllRemotes)
    }

    /// Whether a log loaded with this scope misses what `current` loads: a remote branch in
    /// scope moved, came or went, the toggle changed, or a stash was made or dropped (the
    /// stash set differs, whatever the order: a new or a deleted stash changes what the log
    /// loads). Local branches don't count: their moves already reload the log.
    func isOutdated(by current: HistoryScope) -> Bool {
        remoteTips != current.remoteTips || includesAllRemotes != current.includesAllRemotes
            || stashShas != current.stashShas
    }

    /// `refs` with each remote branch of the scope at the tip it had when the scope was made,
    /// so a log fetched with it is laid out with the tips it loaded until it reloads: a fetch
    /// may move one to a commit the log doesn't have. The same array, storage included, when
    /// none moved.
    func pinning(_ refs: [GitRef]) -> [GitRef] {
        func pinnedTip(_ ref: GitRef) -> String? {
            guard ref.isRemoteBranch, let tip = remoteTips[ref.name], tip != ref.targetSha else { return nil }
            return tip
        }
        guard !remoteTips.isEmpty, refs.contains(where: { pinnedTip($0) != nil }) else { return refs }
        return refs.map { ref in
            guard let tip = pinnedTip(ref) else { return ref }
            return GitRef(name: ref.name, kind: ref.kind, targetSha: tip, isHead: ref.isHead)
        }
    }
}
