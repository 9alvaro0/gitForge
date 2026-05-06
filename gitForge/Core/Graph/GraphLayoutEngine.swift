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
        var endRow: Int  // resolved by end of Pass 1; defaults to last row if still open
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
    static func layouts(for commits: [Commit], refsBySha: [String: [GitRef]] = [:]) -> (rows: [GraphRowLayout], maxLanes: Int) {
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
            lanes.append(LogicalLane(id: id, branchId: branchId, startRow: startRow, endRow: -1))
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

            // Additional parents: reuse a lane already pointing at the parent, or open a new one.
            var mergesOutIds: [Int] = []
            for parent in commit.parentShas.dropFirst() {
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

            rowSlots.append(RowSlots(
                commitLaneId: primaryLaneId,
                lanesAtTopIds: lanesAtTopIds,
                lanesAtBottomIds: lanesAtBottomIds,
                mergesInIds: mergesInIds,
                mergesOutIds: mergesOutIds,
                isMerge: commit.parentShas.count > 1
            ))
        }

        // Lanes that didn't close within the loaded window stay alive through the last row.
        let lastRow = commits.count - 1
        for i in lanes.indices where lanes[i].endRow == -1 {
            lanes[i].endRow = lastRow
        }

        // ── Pass 2 ─────────────────────────────────────────────────────────────
        // Greedy interval scheduling: leftmost free column for each lane.

        // Stable sort: earlier startRow first; ties broken by lane id (= creation order)
        // so the first lane created (typically the active branch tip) stays in column 0.
        let sortedLanes = lanes.sorted {
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

        func occupations(_ ids: [Int]) -> [LaneOccupation] {
            ids.compactMap { id in
                guard let col = laneColumn[id] else { return nil }
                return LaneOccupation(lane: col, branchId: lanes[id].branchId)
            }
        }

        for slots in rowSlots {
            guard let commitLane = laneColumn[slots.commitLaneId] else { continue }
            let commitBranchId = lanes[slots.commitLaneId].branchId

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
                isMerge: slots.isMerge
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
