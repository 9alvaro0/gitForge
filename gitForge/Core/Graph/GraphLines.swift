import Foundation

/// One drawn line: a chain of first parents owned by a single ref.
nonisolated struct GraphLine: Sendable, Equatable {
    let owner: GraphOwner
    /// Rows the line claims, ascending.
    var rows: [Int]
    /// First row the line occupies: `rows[0]` until a merge joins its tip.
    var top: Int
    /// Row of the commit it was born from, when it stops at one already claimed.
    var forkRow: Int?
    /// First parent not loaded: the line runs to the bottom edge.
    var continuesPastEnd: Bool

    /// Last row the line occupies.
    var bottom: Int { forkRow ?? (continuesPastEnd ? Int.max : rows.last ?? top) }
}

/// Stage 1 of the layout: who owns each commit, for drawing and for colour.
nonisolated struct GraphLines: Sendable {
    /// Drawn lines, in walk order.
    var lines: [GraphLine]
    /// Index into `lines` of the line each row belongs to.
    var lineOfRow: [Int]
    /// Owner that decides each row's colour.
    var colorOwnerOfRow: [GraphOwner]

    /// Runs both ownership walks, which share their traversal and differ in
    /// where they start:
    /// - **Drawing** puts HEAD first, so its line runs unbroken down to the root.
    /// - **Colour** has no special start for HEAD, so a commit shared with a
    ///   higher-priority branch keeps that branch's colour.
    static func build(_ input: GraphInput, rowOf: [String: Int]) -> GraphLines {
        let drawn = walk(input, rowOf: rowOf, forDrawing: true)
        let colored = walk(input, rowOf: rowOf, forDrawing: false)
        return GraphLines(
            lines: drawn.lines,
            lineOfRow: drawn.lineOfRow,
            colorOwnerOfRow: colored.lineOfRow.map { colored.lines[$0].owner }
        )
    }
}

// MARK: - Walk

private nonisolated extension GraphLines {
    /// A local branch and the row its line starts at.
    nonisolated struct BranchStart {
        let name: String
        let row: Int
        /// Remote branch whose line this branch continues, so it needs none of its own.
        let continuedRemote: String?
    }

    /// A start competing for rows in the priority order.
    nonisolated struct Candidate {
        let owner: GraphOwner
        let rank: Int
        let row: Int
        /// 1 for a detached HEAD, so a branch on the same commit keeps it.
        let detached: Int
        let name: String

        var sortKey: (Int, Int, Int, String) { (rank, -row, detached, name) }
    }

    static func walk(_ input: GraphInput, rowOf: [String: Int], forDrawing: Bool) -> OwnershipWalk {
        var ownership = OwnershipWalk(commits: input.commits, rowOf: rowOf)
        let branches = branchStarts(input, rowOf: rowOf)
        let headBranch = input.headBranch
        let detachedHeadRow = headBranch == nil ? input.headSha.flatMap { rowOf[$0] } : nil

        // 1. HEAD goes first, only when drawing.
        if forDrawing {
            if let headBranch {
                if let start = branches.first(where: { $0.name == headBranch }) {
                    ownership.claim(.branch(headBranch), from: start.row)
                }
            } else if let detachedHeadRow {
                ownership.claim(.head, from: detachedHeadRow)
            }
        }

        // 2. Local branches and remote trunks by priority, the lowest tip first within a
        //    level. A remote trunk ranks as the trunk it stands in for. When colouring,
        //    HEAD takes part like any other.
        var candidates = branches
            .filter { !forDrawing || $0.name != headBranch }
            .map { Candidate(owner: .branch($0.name), rank: GraphPriority.rank($0.name),
                             row: $0.row, detached: 0, name: $0.name) }
        candidates += remoteTrunkCandidates(input, rowOf: rowOf)
        if !forDrawing, let detachedHeadRow {
            candidates.append(Candidate(owner: .head, rank: 4, row: detachedHeadRow, detached: 1, name: ""))
        }
        for candidate in candidates.sorted(by: { $0.sortKey < $1.sortKey }) {
            ownership.claim(candidate.owner, from: candidate.row)
        }

        // 3. Remote branches that continue no local one and are no trunk, top to bottom.
        let continued = Set(branches.compactMap(\.continuedRemote))
        let remotes = input.refs
            .filter { $0.isRemoteBranch && !continued.contains($0.name) && input.remoteTrunks[$0.name] == nil }
            .compactMap { ref in rowOf[ref.targetSha].map { (name: ref.name, row: $0) } }
        for remote in remotes.sorted(by: { (-$0.row, $0.name) < (-$1.row, $1.name) }) {
            ownership.claim(.remote(remote.name), from: remote.row)
        }

        // 4. Stashes claim only their own row.
        let stashRows = input.stashShas.compactMap { sha in rowOf[sha].map { (sha: sha, row: $0) } }
        for stash in stashRows.sorted(by: { $0.row < $1.row }) {
            ownership.claim(.stash(stash.sha), from: stash.row, ownRowOnly: true)
        }

        // 5. Whatever no ref reaches, top to bottom.
        ownership.claimUnowned()
        return ownership
    }

    /// Remote trunks with a loaded tip, ready to claim in step 2 with their trunk's rank.
    static func remoteTrunkCandidates(_ input: GraphInput, rowOf: [String: Int]) -> [Candidate] {
        input.refs.compactMap { ref in
            guard ref.isRemoteBranch, let rank = input.remoteTrunks[ref.name], let row = rowOf[ref.targetSha] else { return nil }
            return Candidate(owner: .remote(ref.name), rank: rank, row: row, detached: 0, name: ref.name)
        }
    }

    /// Local branches with a loaded start. One that is only behind its upstream
    /// starts at the upstream's tip, so the line spans what a pull would bring,
    /// unless that upstream is a remote trunk, which has its own line. It does
    /// so whether its own tip is loaded or not, so the line is the same before
    /// and after the page holding that tip loads (§3.9). Any other branch starts
    /// at its own tip, once loaded.
    static func branchStarts(_ input: GraphInput, rowOf: [String: Int]) -> [BranchStart] {
        var remoteRows: [String: Int] = [:]
        for ref in input.refs where ref.isRemoteBranch {
            if let row = rowOf[ref.targetSha], remoteRows[ref.name] == nil {
                remoteRows[ref.name] = row
            }
        }
        return input.refs.compactMap { ref in
            guard ref.isLocalBranch else { return nil }
            if let upstream = ref.upstream, input.remoteTrunks[upstream] == nil, let upstreamRow = remoteRows[upstream],
               (ref.ahead ?? 0) == 0, (ref.behind ?? 0) > 0 {
                return BranchStart(name: ref.name, row: upstreamRow, continuedRemote: upstream)
            }
            guard let tipRow = rowOf[ref.targetSha] else { return nil }
            return BranchStart(name: ref.name, row: tipRow, continuedRemote: nil)
        }
    }
}

/// Claims rows for owners, one start at a time.
private nonisolated struct OwnershipWalk {
    let commits: [Commit]
    let rowOf: [String: Int]
    private(set) var lines: [GraphLine] = []
    /// Index into `lines` per row; -1 while unowned.
    private(set) var lineOfRow: [Int]

    init(commits: [Commit], rowOf: [String: Int]) {
        self.commits = commits
        self.rowOf = rowOf
        lineOfRow = Array(repeating: -1, count: commits.count)
    }

    /// Walks down the first parents from `startRow`, claiming rows nobody owns
    /// yet. Stops at the first owned row (the line's `forkRow`), at a root, or
    /// at a parent that is not loaded. A start whose row is already owned adds
    /// no line. With `ownRowOnly` (stashes) it claims `startRow` alone and
    /// never descends.
    mutating func claim(_ owner: GraphOwner, from startRow: Int, ownRowOnly: Bool = false) {
        guard lineOfRow[startRow] < 0 else { return }
        let index = lines.count
        var rows: [Int] = []
        var forkRow: Int?
        var continuesPastEnd = false
        var row = startRow
        while true {
            lineOfRow[row] = index
            rows.append(row)
            guard let parent = commits[row].parentShas.first else { break }
            guard let parentRow = rowOf[parent] else {
                continuesPastEnd = true
                break
            }
            if ownRowOnly || lineOfRow[parentRow] >= 0 {
                forkRow = parentRow
                break
            }
            row = parentRow
        }
        lines.append(GraphLine(owner: owner, rows: rows, top: startRow,
                               forkRow: forkRow, continuesPastEnd: continuesPastEnd))
    }

    /// Gives every row still unowned to an unnamed line, top to bottom.
    mutating func claimUnowned() {
        for row in lineOfRow.indices where lineOfRow[row] < 0 {
            claim(.unnamed(row), from: row)
        }
    }
}
