import Foundation

enum GraphLayoutEngine {
    private struct LaneState: Sendable, Hashable {
        let sha: String
        let branchId: Int
    }

    /// Computes per-row graph layout for an ordered list of commits (newest first, the order
    /// `git log --topo-order` emits). Branches keep a stable `branchId` for the renderer to
    /// color by branch identity instead of column index.
    static func layouts(for commits: [Commit]) -> (rows: [GraphRowLayout], maxLanes: Int) {
        var lanes: [LaneState?] = []
        var rows: [GraphRowLayout] = []
        rows.reserveCapacity(commits.count)
        var maxLanes = 0
        var nextBranchId = 0

        for commit in commits {
            // 1. Find lanes already pointing at this commit (could be more than one in a merge).
            let allMatches = lanes.indices.filter { lanes[$0]?.sha == commit.sha }
            let commitLane: Int
            let commitBranchId: Int
            if let primary = allMatches.first, let state = lanes[primary] {
                commitLane = primary
                commitBranchId = state.branchId
            } else {
                commitBranchId = nextBranchId
                nextBranchId += 1
                if let nilIndex = lanes.firstIndex(where: { $0 == nil }) {
                    lanes[nilIndex] = LaneState(sha: commit.sha, branchId: commitBranchId)
                    commitLane = nilIndex
                } else {
                    lanes.append(LaneState(sha: commit.sha, branchId: commitBranchId))
                    commitLane = lanes.count - 1
                }
            }

            // Snapshot active lanes (top half) before mutating.
            let lanesAtTop = lanes.enumerated().compactMap { index, state -> LaneOccupation? in
                guard let state else { return nil }
                return LaneOccupation(lane: index, branchId: state.branchId)
            }

            // 2. mergesIn = other lanes that pointed at this commit and now collapse into it.
            let mergesIn: [LaneOccupation] = allMatches.compactMap { index in
                guard index != commitLane, let state = lanes[index] else { return nil }
                return LaneOccupation(lane: index, branchId: state.branchId)
            }
            for merge in mergesIn { lanes[merge.lane] = nil }

            // 3. First parent stays on the commit's lane (same branch identity).
            if let firstParent = commit.parentShas.first {
                lanes[commitLane] = LaneState(sha: firstParent, branchId: commitBranchId)
            } else {
                lanes[commitLane] = nil
            }

            // 4. Additional parents: connect to existing lane or allocate a new one near the commit.
            var mergesOut: [LaneOccupation] = []
            for parent in commit.parentShas.dropFirst() {
                if let existing = lanes.firstIndex(where: { $0?.sha == parent }), let state = lanes[existing] {
                    mergesOut.append(LaneOccupation(lane: existing, branchId: state.branchId))
                } else {
                    let newBranchId = nextBranchId
                    nextBranchId += 1
                    let lane = allocateLaneNear(commitLane: commitLane, lanes: &lanes, sha: parent, branchId: newBranchId)
                    mergesOut.append(LaneOccupation(lane: lane, branchId: newBranchId))
                }
            }

            // 5. Trim trailing nil lanes (avoid the column array growing forever).
            while lanes.last == nil { lanes.removeLast() }

            // Snapshot active lanes (bottom half).
            let lanesAtBottom = lanes.enumerated().compactMap { index, state -> LaneOccupation? in
                guard let state else { return nil }
                return LaneOccupation(lane: index, branchId: state.branchId)
            }

            let allLaneIndices = lanesAtTop.map(\.lane)
                + lanesAtBottom.map(\.lane)
                + mergesIn.map(\.lane)
                + mergesOut.map(\.lane)
                + [commitLane]
            let rowTotal = (allLaneIndices.max() ?? 0) + 1
            maxLanes = max(maxLanes, rowTotal)

            rows.append(GraphRowLayout(
                commitLane: commitLane,
                commitBranchId: commitBranchId,
                lanesAtTop: lanesAtTop,
                lanesAtBottom: lanesAtBottom,
                mergesIn: mergesIn,
                mergesOut: mergesOut,
                totalLanes: rowTotal,
                isMerge: commit.parentShas.count > 1
            ))
        }

        return (rows, maxLanes)
    }

    /// Allocates a slot near `commitLane`. Bias is right-of-commit first (the typical convention
    /// for "merged-from" branches), then left, then append. This keeps merge curves short.
    private static func allocateLaneNear(commitLane: Int, lanes: inout [LaneState?], sha: String, branchId: Int) -> Int {
        for index in (commitLane + 1)..<lanes.count {
            if lanes[index] == nil {
                lanes[index] = LaneState(sha: sha, branchId: branchId)
                return index
            }
        }
        if commitLane > 0 {
            for index in stride(from: commitLane - 1, through: 0, by: -1) {
                if lanes[index] == nil {
                    lanes[index] = LaneState(sha: sha, branchId: branchId)
                    return index
                }
            }
        }
        lanes.append(LaneState(sha: sha, branchId: branchId))
        return lanes.count - 1
    }
}
