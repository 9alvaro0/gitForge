import Foundation

/// Which remote branches stand in for a local trunk that doesn't exist (§3.1).
nonisolated enum GraphTrunks {
    /// The remote branches that stand in for a missing local trunk, by name ("origin/main"),
    /// with the rank of the trunk they replace.
    ///
    /// The remote is `origin` when it has branches, otherwise the first by name.
    /// - **Main (rank 0)**, when no local `main`/`master`/`trunk` exists: the branch
    ///   the remote's HEAD points at, unless that is a rank-1 branch; failing that, the
    ///   first of `main`, `master` and `trunk` the remote has.
    /// - **Develop (rank 1)**, when no local `develop`/`dev` exists: the first of
    ///   `develop` and `dev` the remote has.
    ///
    /// A remote branch that a local branch tracks, or whose name without the remote a local
    /// branch has, is never a stand-in, by HEAD or by name: the local branch draws that line.
    /// A remote HEAD on a default branch checked out locally (`canary`) picks nothing, and
    /// `main`, `master` or `trunk` may still stand in.
    ///
    /// `remoteHeads` maps each remote to the branch its HEAD points at, "origin" → "origin/main".
    /// A HEAD that names no existing branch of that remote counts for nothing.
    static func remoteStandIns(refs: [GitRef], remoteHeads: [String: String]) -> [String: Int] {
        var branchesOfRemote: [String: Set<String>] = [:]
        var localNames: Set<String> = []
        var trackedNames: Set<String> = []
        for ref in refs {
            switch ref.kind {
            case .remoteBranch(let remote): branchesOfRemote[remote, default: []].insert(ref.name)
            case .localBranch:
                localNames.insert(ref.name)
                if let upstream = ref.upstream { trackedNames.insert(upstream) }
            case .tag: break
            }
        }
        let remote = branchesOfRemote["origin"] != nil ? "origin" : branchesOfRemote.keys.min()
        guard let remote, let branches = branchesOfRemote[remote] else { return [:] }

        // "origin/main" → "main"; the rank is that of the name without the remote.
        func shortName(_ name: String) -> String { String(name.dropFirst(remote.count + 1)) }
        // An existing branch of the remote that no local branch tracks or is named like.
        func canStandIn(_ name: String) -> Bool {
            branches.contains(name) && !trackedNames.contains(name) && !localNames.contains(shortName(name))
        }
        func firstCandidate(_ names: [String]) -> String? {
            names.map { "\(remote)/\($0)" }.first(where: canStandIn)
        }
        func hasLocal(rank: Int) -> Bool { localNames.contains { GraphPriority.rank($0) == rank } }

        var standIns: [String: Int] = [:]
        if !hasLocal(rank: 0) {
            var main = firstCandidate(["main", "master", "trunk"])
            if let head = remoteHeads[remote], canStandIn(head), GraphPriority.rank(shortName(head)) != 1 {
                main = head
            }
            if let main { standIns[main] = 0 }
        }
        if !hasLocal(rank: 1), let develop = firstCandidate(["develop", "dev"]) {
            standIns[develop] = 1
        }
        return standIns
    }
}
