import Foundation

/// Two-pass branch-aware graph layout.
///
/// Pass 1 walks the topo-ordered log and resolves *logical lanes*: each lane is the
/// contiguous chain of SHAs that share a first-parent ancestry, with a `[startRow,
/// endRow]` lifetime. No column is assigned yet — only identity, color, and lifetime.
///
/// Pass 2 packs those lifetimes into the fewest columns possible via greedy interval
/// scheduling: lanes are sorted by `startRow` and each one takes the leftmost column
/// whose previous tenant has already closed. Two lanes with disjoint lifetimes share
/// a column, so a `release/*` tip that lives 50 rows no longer permanently blocks a
/// slot for unrelated branches that come and go.
///
/// Pass 3 emits the renderer-friendly `GraphRowLayout` per commit.
enum GraphLayoutEngine {
    private struct LogicalLane {
        let id: Int
        let branchId: Int
        let startRow: Int
        /// Display name of the ref pointing at this lane's tip when it was
        /// opened. Used to pin gitflow trunks (main, develop, release/*) to
        /// stable leftmost columns.
        let initialRefName: String?
        /// True when the lane originates from a stash commit. Propagates into
        /// `LaneOccupation.isStash` so the renderer can draw it dashed.
        let isStash: Bool
        var endRow: Int  // resolved by end of Pass 1; defaults to last row if still open
    }

    /// Lower rank = leftmost column. `nil` (default `Int.max`) keeps the
    /// existing greedy assignment for non-trunk lanes. Order matches a typical
    /// gitflow read: trunk (main/master) first, then develop, then release
    /// branches, then trunk-equivalent legacy names.
    nonisolated(unsafe) private static let priorityPatterns: [(matcher: (String) -> Bool, rank: Int)] = [
        ({ $0 == "main" || $0 == "master" }, 0),
        ({ $0 == "develop" || $0 == "dev"  }, 1),
        ({ $0.hasPrefix("release/")        }, 2),
        ({ $0 == "trunk"                   }, 3),
    ]

    nonisolated static func priorityRank(forName name: String) -> Int? {
        priorityPatterns.first { $0.matcher(name) }?.rank
    }

    private struct RowSlots {
        let commitLaneId: Int
        let lanesAtTopIds: [Int]
        let lanesAtBottomIds: [Int]
        let mergesInIds: [Int]
        let mergesOutIds: [Int]
        let isMerge: Bool
    }

    /// Computes per-row graph layout for an ordered list of commits (newest first, the
    /// order `git log --topo-order` emits). When `refsBySha` is provided, lanes derive
    /// their `branchId` from the ref's folder prefix so sibling branches share a color.
    /// `stashShas` marks lanes opened directly at a stash commit so the renderer can
    /// draw them dashed.
    static func layouts(
        for commits: [Commit],
        refsBySha: [String: [GitRef]] = [:],
        stashShas: Set<String> = []
    ) -> (rows: [GraphRowLayout], maxLanes: Int) {
        guard !commits.isEmpty else { return ([], 1) }

        // ── Pass 1 ─────────────────────────────────────────────────────────────
        // Walk the log and build logical lanes + per-row slot ids.

        var lanes: [LogicalLane] = []
        var laneCurrentSha: [Int: String] = [:]
        var rowSlots: [RowSlots] = []
        rowSlots.reserveCapacity(commits.count)
        var nextLaneId = 0
        var nextSequentialBranchId = 100_000

        func makeBranchId(forSha sha: String) -> Int {
            if let ref = refsBySha[sha]?.preferredForGraph(),
               let id = Self.branchId(for: ref) {
                return id
            }
            defer { nextSequentialBranchId += 1 }
            return nextSequentialBranchId
        }

        func openLane(branchId: Int, currentSha: String, startRow: Int) -> Int {
            let id = nextLaneId
            nextLaneId += 1
            let initialRef = refsBySha[currentSha]?.preferredForGraph()
            lanes.append(LogicalLane(
                id: id,
                branchId: branchId,
                startRow: startRow,
                initialRefName: initialRef?.displayName,
                isStash: stashShas.contains(currentSha),
                endRow: -1
            ))
            laneCurrentSha[id] = currentSha
            return id
        }

        func closeLane(_ id: Int, atRow row: Int) {
            lanes[id].endRow = row
            laneCurrentSha.removeValue(forKey: id)
        }

        for (rowIdx, commit) in commits.enumerated() {
            // Snapshot active lane ids BEFORE any mutation. Sorted for deterministic order.
            let lanesAtTopIds = laneCurrentSha.keys.sorted()

            // Lanes whose `currentSha` is this commit's sha. Multiple if branches converge.
            let matching = laneCurrentSha
                .filter { $0.value == commit.sha }
                .keys
                .sorted()

            let primaryLaneId: Int
            let mergesInIds: [Int]
            if let first = matching.first {
                primaryLaneId = first
                mergesInIds = Array(matching.dropFirst())
            } else {
                // Brand-new lane (this commit is a tip with no incoming pointer).
                primaryLaneId = openLane(
                    branchId: makeBranchId(forSha: commit.sha),
                    currentSha: commit.sha,
                    startRow: rowIdx
                )
                mergesInIds = []
            }

            // Close merges-in: those lanes' final appearance is this row.
            for mid in mergesInIds { closeLane(mid, atRow: rowIdx) }

            // First parent inherits the primary lane (same branch identity).
            if let firstParent = commit.parentShas.first {
                laneCurrentSha[primaryLaneId] = firstParent
            } else {
                // Root commit: primary lane's last row is this one.
                closeLane(primaryLaneId, atRow: rowIdx)
            }

            // Stash commits have 2-3 parents (HEAD-when-stashed, index tree, optional
            // untracked tree). Only `parent[0]` is meaningful for the graph — the
            // others are ephemeral trees with no shared ancestry, so opening lanes
            // for them produces dangling "ghost branches" that look broken. Treat
            // a stash as if it were linear (single-parent) for layout purposes,
            // which is how GitKraken/Fork render them.
            let isStashCommit = stashShas.contains(commit.sha)
            let extraParents = isStashCommit ? [] : Array(commit.parentShas.dropFirst())

            // Additional parents: reuse a lane already pointing at the parent, or open a new one.
            var mergesOutIds: [Int] = []
            for parent in extraParents {
                if let existing = laneCurrentSha.first(where: { $0.value == parent })?.key {
                    mergesOutIds.append(existing)
                } else {
                    let newId = openLane(
                        branchId: makeBranchId(forSha: parent),
                        currentSha: parent,
                        startRow: rowIdx
                    )
                    mergesOutIds.append(newId)
                }
            }

            let lanesAtBottomIds = laneCurrentSha.keys.sorted()

            // A stash is *technically* a merge (2-3 parents) but visually we want
            // it to read as a single-point side note, not a merge node — the hollow
            // merge dot would compete with the distinct stash glyph the renderer
            // draws.
            rowSlots.append(RowSlots(
                commitLaneId: primaryLaneId,
                lanesAtTopIds: lanesAtTopIds,
                lanesAtBottomIds: lanesAtBottomIds,
                mergesInIds: mergesInIds,
                mergesOutIds: mergesOutIds,
                isMerge: !isStashCommit && commit.parentShas.count > 1
            ))
        }

        // Lanes that didn't close within the loaded window stay alive through the last row.
        let lastRow = commits.count - 1
        for i in lanes.indices where lanes[i].endRow == -1 {
            lanes[i].endRow = lastRow
        }

        // ── Pass 2 ─────────────────────────────────────────────────────────────
        // Greedy interval scheduling: leftmost free column for each lane.

        // Sort: gitflow trunks (main/master, develop, release/*) first by their
        // priority rank so they grab the leftmost columns and stay there for
        // their entire lifetime. Everything else falls back to (startRow, id),
        // preserving the previous greedy layout for feature/* and friends.
        let sortedLanes = lanes.sorted {
            let aRank = $0.initialRefName.flatMap(Self.priorityRank(forName:)) ?? Int.max
            let bRank = $1.initialRefName.flatMap(Self.priorityRank(forName:)) ?? Int.max
            if aRank != bRank { return aRank < bRank }
            if $0.startRow != $1.startRow { return $0.startRow < $1.startRow }
            return $0.id < $1.id
        }

        var laneColumn: [Int: Int] = [:]
        laneColumn.reserveCapacity(lanes.count)
        // For each column, the endRow of its current tenant. A new lane can take this
        // column only if its startRow > columnLastEndRow[col].
        var columnLastEndRow: [Int] = []

        for lane in sortedLanes {
            var assigned: Int?
            for col in 0..<columnLastEndRow.count {
                if columnLastEndRow[col] < lane.startRow {
                    assigned = col
                    break
                }
            }
            if let col = assigned {
                laneColumn[lane.id] = col
                columnLastEndRow[col] = lane.endRow
            } else {
                let newCol = columnLastEndRow.count
                laneColumn[lane.id] = newCol
                columnLastEndRow.append(lane.endRow)
            }
        }

        // ── Pass 3 ─────────────────────────────────────────────────────────────
        // Materialize GraphRowLayout per commit using the column assignment.

        var graphRows: [GraphRowLayout] = []
        graphRows.reserveCapacity(commits.count)
        var maxLanes = 1

        func priorityRank(forLaneId id: Int) -> Int? {
            lanes[id].initialRefName.flatMap(Self.priorityRank(forName:))
        }

        func occupations(_ ids: [Int]) -> [LaneOccupation] {
            ids.compactMap { id in
                guard let col = laneColumn[id] else { return nil }
                return LaneOccupation(
                    lane: col,
                    branchId: lanes[id].branchId,
                    priorityRank: priorityRank(forLaneId: id),
                    isStash: lanes[id].isStash
                )
            }
        }

        for slots in rowSlots {
            guard let commitLane = laneColumn[slots.commitLaneId] else { continue }
            let commitBranchId = lanes[slots.commitLaneId].branchId
            let commitPriorityRank = priorityRank(forLaneId: slots.commitLaneId)
            let commitIsStash = lanes[slots.commitLaneId].isStash

            let lanesAtTop = occupations(slots.lanesAtTopIds)
            let lanesAtBottom = occupations(slots.lanesAtBottomIds)
            let mergesIn = occupations(slots.mergesInIds)
            let mergesOut = occupations(slots.mergesOutIds)

            let allCols = lanesAtTop.map(\.lane)
                + lanesAtBottom.map(\.lane)
                + mergesIn.map(\.lane)
                + mergesOut.map(\.lane)
                + [commitLane]
            let totalLanes = (allCols.max() ?? 0) + 1
            maxLanes = max(maxLanes, totalLanes)

            graphRows.append(GraphRowLayout(
                commitLane: commitLane,
                commitBranchId: commitBranchId,
                lanesAtTop: lanesAtTop,
                lanesAtBottom: lanesAtBottom,
                mergesIn: mergesIn,
                mergesOut: mergesOut,
                totalLanes: totalLanes,
                isMerge: slots.isMerge,
                commitPriorityRank: commitPriorityRank,
                commitIsStash: commitIsStash
            ))
        }

        return (graphRows, maxLanes)
    }

    /// Stable hash of the full ref name → distinct hue per branch. Sibling branches
    /// (`release/1.0.13` vs `release/1.0.14`) are simultaneously alive in the log,
    /// so they need contrasting colors — grouping by prefix made them blend into a
    /// single mass.
    static func branchId(for ref: GitRef) -> Int? {
        var h: Int = 0
        for c in ref.displayName.unicodeScalars { h = (h &* 31) &+ Int(c.value) }
        return abs(h) % 99_999
    }
}

private extension Array where Element == GitRef {
    /// Pick the most "interesting" ref to derive a graph color from.
    /// HEAD-tagged > local branch > remote branch > tag.
    func preferredForGraph() -> GitRef? {
        if let head = first(where: { $0.isHead }) { return head }
        if let local = first(where: { $0.isLocalBranch }) { return local }
        if let remote = first(where: { $0.isRemoteBranch }) { return remote }
        return first
    }
}
