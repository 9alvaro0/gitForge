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
    /// Remote branches standing in for a local trunk that doesn't exist (§3.1), by name
    /// ("origin/main"), with the rank of the trunk they replace: 0 for main, 1 for develop.
    var remoteTrunks: [String: Int] = [:]
    /// The working tree has uncommitted changes (§3.5): a connector runs from the
    /// Uncommitted changes row down column 0 to HEAD's commit, and HEAD's branch never
    /// continues its upstream, which draws what a pull would bring beside it instead.
    var hasUncommittedChanges = false
}

nonisolated extension GraphInput {
    /// Local branch with `isHead`; nil when detached.
    var headBranch: String? {
        refs.first { $0.isLocalBranch && $0.isHead }?.name
    }

    /// Uncommitted changes, a HEAD and at least one row: the layout runs the connector.
    var drawsUncommittedConnector: Bool {
        hasUncommittedChanges && headSha != nil && !commits.isEmpty
    }

    /// Priority rank of a branch owner: a local branch by its name, a remote trunk by the
    /// trunk it stands in for. Nil for any other owner.
    func rank(of owner: GraphOwner) -> Int? {
        switch owner {
        case .branch(let name): GraphPriority.rank(name)
        case .remote(let name): remoteTrunks[name]
        case .head, .stash, .unnamed: nil
        }
    }

    /// End of the first loaded page: the only one whose lines may reserve
    /// columns up front.
    var firstPageEnd: Int { pageEnds.first ?? commits.count }

    /// End of the page that holds `row`: the first page end past it, or the
    /// end of the log. Binary search, since the engine asks once per merge.
    func pageEnd(containing row: Int) -> Int {
        let next = pageEnds.upperBound(of: row)
        return next < pageEnds.count ? pageEnds[next] : commits.count
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

nonisolated extension Array where Element == Int {
    /// Index of the first element greater than `value`, or `count` when none
    /// is. The array must be ascending; O(log n).
    func upperBound(of value: Int) -> Int {
        var low = 0
        var high = count
        while low < high {
            let middle = low + (high - low) / 2
            if self[middle] > value { high = middle } else { low = middle + 1 }
        }
        return low
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
