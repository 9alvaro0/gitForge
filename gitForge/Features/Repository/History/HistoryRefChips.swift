import Foundation

/// The refs History draws as chips, and how each one looks (§4.4). Made from the refs and the
/// remote trunks a layout was laid out with, so the chips change in the same turn as the graph.
nonisolated struct HistoryRefChips: Sendable, Equatable {
    /// Refs drawn as chips on each commit. Without every remote branch, a remote one has a chip
    /// only when a local branch tracks it or it is a remote trunk (§4.4).
    let refsBySha: [String: [GitRef]]
    /// Remote branches not on the commit of the local branch that tracks them.
    let awayFromLocal: Set<String>
    /// Remote branches whose name another remote branch with a chip shares.
    let prefixed: Set<String>

    static let empty = HistoryRefChips(refsBySha: [:], awayFromLocal: [], prefixed: [])

    /// `refs` in the order given, grouped by commit. A remote branch is left out unless
    /// `includesAllRemotes`, a local branch tracks it (`upstream`) or it is in `remoteTrunks`.
    static func make(refs: [GitRef], remoteTrunks: [String: Int], includesAllRemotes: Bool) -> HistoryRefChips {
        // Commits of the local branches that track each remote branch.
        var trackerShas: [String: Set<String>] = [:]
        for ref in refs where ref.isLocalBranch {
            if let upstream = ref.upstream { trackerShas[upstream, default: []].insert(ref.targetSha) }
        }

        let shown = refs.filter { ref in
            !ref.isRemoteBranch || includesAllRemotes || trackerShas[ref.name] != nil || remoteTrunks[ref.name] != nil
        }

        var away: Set<String> = []
        var remotesByBranch: [String: [String]] = [:]
        for ref in shown where ref.isRemoteBranch {
            remotesByBranch[ref.displayName, default: []].append(ref.name)
            if let shas = trackerShas[ref.name], !shas.contains(ref.targetSha) { away.insert(ref.name) }
        }
        let prefixed = Set(remotesByBranch.values.filter { $0.count > 1 }.joined())

        return HistoryRefChips(refsBySha: Dictionary(grouping: shown, by: \.targetSha),
                               awayFromLocal: away, prefixed: prefixed)
    }

    func refs(on sha: String) -> [GitRef] {
        refsBySha[sha] ?? []
    }

    /// The chip's name: `displayName`, or the full name ("origin/main") when prefixed.
    func label(for ref: GitRef) -> String {
        prefixed.contains(ref.name) ? ref.name : ref.displayName
    }

    /// Dashed border: a remote branch on a ghost commit or away from its local branch.
    func isDashed(_ ref: GitRef, onGhost: Bool) -> Bool {
        ref.isRemoteBranch && (onGhost || awayFromLocal.contains(ref.name))
    }
}
