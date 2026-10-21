import Foundation

/// Stage 4 of the layout: the ghost rows, commits reachable from a remote
/// branch and from no local ref (§4.3).
///
/// One top-down pass. Every row carries two marks, "reached from local" and
/// "reached from remote". The tips seed them: HEAD, local branches and stashes
/// seed the local mark, remote branches seed the remote mark, and tags seed
/// nothing, so a tag fetched onto a remote commit does not make it local.
/// Parents always sit on later rows, so a row's marks are complete when the
/// pass reaches it, and the row hands them to every loaded parent. Parents
/// that are not loaded stop the walk.
nonisolated enum GraphReachability {
    /// Ghost flag of each row of `input.commits`. `rowOf` maps each sha to its
    /// row, as `GraphInput.rowIndex()` returns it.
    static func ghostRows(_ input: GraphInput, rowOf: [String: Int]) -> [Bool] {
        var marks = Array(repeating: Reach(), count: input.commits.count)
        for (sha, reach) in tips(input) {
            if let row = rowOf[sha] {
                marks[row].formUnion(reach)
            }
        }
        for (row, commit) in input.commits.enumerated() {
            let reach = marks[row]
            for parent in commit.parentShas {
                if let parentRow = rowOf[parent] {
                    marks[parentRow].formUnion(reach)
                }
            }
        }
        return marks.map { $0.contains(.remote) && !$0.contains(.local) }
    }
}

// MARK: - Tips

private nonisolated extension GraphReachability {
    /// The two marks a commit can carry.
    nonisolated struct Reach: OptionSet, Sendable {
        let rawValue: UInt8

        static let local = Reach(rawValue: 1 << 0)
        static let remote = Reach(rawValue: 1 << 1)
    }

    /// Every sha a ref or stash points at, with the mark it seeds. Tags are left out.
    static func tips(_ input: GraphInput) -> [(sha: String, reach: Reach)] {
        var tips: [(sha: String, reach: Reach)] = []
        tips.reserveCapacity(input.refs.count + input.stashShas.count + 1)
        if let head = input.headSha {
            tips.append((head, .local))
        }
        for ref in input.refs {
            if ref.isLocalBranch {
                tips.append((ref.targetSha, .local))
            } else if ref.isRemoteBranch {
                tips.append((ref.targetSha, .remote))
            }
        }
        for stash in input.stashShas {
            tips.append((stash, .local))
        }
        return tips
    }
}
