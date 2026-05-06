import Foundation

enum GraphLayoutEngine {
    private struct LaneState: Sendable, Hashable {
        let sha: String
        let branchId: Int
    }

    /// Computes per-row graph layout for an ordered list of commits (newest first, the order
    /// `git log --topo-order` emits). When `refsBySha` is provided, brand-new tip commits
    /// take a `branchId` derived from their ref's folder prefix (`feature/`, `release/`, …)
    /// so sibling branches share a lane color in the renderer instead of each getting a
    /// unique one. Commits without a tip ref fall back to a sequential id.
    static func layouts(for commits: [Commit], refsBySha: [String: [GitRef]] = [:]) -> (rows: [GraphRowLayout], maxLanes: Int) {
        var lanes: [LaneState?] = []
        var rows: [GraphRowLayout] = []
        rows.reserveCapacity(commits.count)
        var maxLanes = 0
        var nextSequentialId = 100_000

        // Returns a deterministic id derived from a branch's folder prefix
        // (e.g. "release" / "feature") if there's a ref pointing at this sha;
        // otherwise allocates a fresh sequential id far from the prefix range.
        func branchId(for sha: String) -> Int {
            if let ref = refsBySha[sha]?.preferredForGraph(),
               let id = Self.prefixBranchId(for: ref) {
                return id
            }
            defer { nextSequentialId += 1 }
            return nextSequentialId
        }

        for commit in commits {
            // Snapshot lanes BEFORE any mutation. This is what "comes in from above" — a brand
            // new tip is NOT in this snapshot, so the renderer won't draw a top-half stub for it.
            let lanesAtTop = lanes.enumerated().compactMap { index, state -> LaneOccupation? in
                guard let state else { return nil }
                return LaneOccupation(lane: index, branchId: state.branchId)
            }

            // 1. Find lanes already pointing at this commit (could be more than one in a merge).
            let allMatches = lanes.indices.filter { lanes[$0]?.sha == commit.sha }
            let commitLane: Int
            let commitBranchId: Int
            if let primary = allMatches.first, let state = lanes[primary] {
                commitLane = primary
                commitBranchId = state.branchId
            } else {
                commitBranchId = branchId(for: commit.sha)
                if let nilIndex = lanes.firstIndex(where: { $0 == nil }) {
                    lanes[nilIndex] = LaneState(sha: commit.sha, branchId: commitBranchId)
                    commitLane = nilIndex
                } else {
                    lanes.append(LaneState(sha: commit.sha, branchId: commitBranchId))
                    commitLane = lanes.count - 1
                }
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
                    let newBranchId = branchId(for: parent)
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

    /// Maps a `GitRef` to a branchId derived from its folder prefix. Refs
    /// without a `/` (e.g. `main`) get an id derived from the full name so
    /// they don't collide with each other. Returns `nil` if we shouldn't
    /// derive a branchId (no ref / non-branch ref).
    static func prefixBranchId(for ref: GitRef) -> Int? {
        let segments = ref.displayName.split(separator: "/", omittingEmptySubsequences: true)
        let key: String
        if segments.count >= 2 {
            // "feature/RESAL-123" → "feature", "release/1.0.10" → "release", …
            key = String(segments[0])
        } else {
            key = ref.displayName
        }
        // Stable hash within Int range; offset by a small base so the prefix-
        // bucket ids don't overlap with sequential ids (which start at 100_000).
        var h: Int = 0
        for c in key.unicodeScalars { h = (h &* 31) &+ Int(c.value) }
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
