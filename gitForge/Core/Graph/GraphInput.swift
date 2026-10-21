import Foundation

/// Everything the commit graph engine reads. `commits` are topologically
/// ordered, newest first, so a parent always sits on a later row than its
/// children.
nonisolated struct GraphInput: Sendable {
    var commits: [Commit]
    /// Row index one past the end of each loaded page, ascending. Empty means one page.
    var pageEnds: [Int] = []
    var headSha: String? = nil
    /// Local branches, remote branches and tags, as `GitCLI.refs()` returns them.
    var refs: [GitRef] = []
    var stashShas: Set<String> = []
    /// Number of pool colours for the current accent (`LaneColors.pool(accent:).count`).
    var paletteSize: Int = 4
}

nonisolated extension GraphInput {
    /// Local branch with `isHead`; nil when detached.
    var headBranch: String? {
        refs.first { $0.isLocalBranch && $0.isHead }?.name
    }

    /// End of the first loaded page: the only one whose lines may reserve
    /// columns up front.
    var firstPageEnd: Int { pageEnds.first ?? commits.count }

    /// End of the page that holds `row`.
    func pageEnd(containing row: Int) -> Int {
        pageEnds.first { $0 > row } ?? commits.count
    }

    /// Row of every commit by sha. A sha that appears twice keeps its first row.
    func rowIndex() -> [String: Int] {
        var rows: [String: Int] = [:]
        rows.reserveCapacity(commits.count)
        for (row, commit) in commits.enumerated() where rows[commit.sha] == nil {
            rows[commit.sha] = row
        }
        return rows
    }
}

/// Who a line or a commit's colour belongs to.
nonisolated enum GraphOwner: Hashable, Sendable {
    /// Detached HEAD.
    case head
    /// Local branch name.
    case branch(String)
    /// Remote ref name, "origin/x".
    case remote(String)
    /// Stash sha.
    case stash(String)
    /// First row of a chain no ref reaches.
    case unnamed(Int)
}

nonisolated enum GraphPriority {
    /// Lower ranks claim commits first and sit further left: trunk, develop,
    /// releases, hotfixes, then everything else.
    static func rank(_ branchName: String) -> Int {
        switch branchName {
        case "main", "master", "trunk": 0
        case "develop", "dev": 1
        case _ where branchName.hasPrefix("release/"): 2
        case _ where branchName.hasPrefix("hotfix/"): 3
        default: 4
        }
    }
}
