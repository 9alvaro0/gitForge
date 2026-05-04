import Foundation

enum GraphLayoutEngine {
    /// Computes per-row graph layout for an ordered list of commits (newest first, the order
    /// `git log` emits). The lane state evolves top-to-bottom as commits are consumed.
    static func layouts(for commits: [Commit]) -> (rows: [GraphRowLayout], maxLanes: Int) {
        var lanes: [String?] = []
        var rows: [GraphRowLayout] = []
        rows.reserveCapacity(commits.count)
        var maxLanes = 0

        for commit in commits {
            let allMatches = lanes.indices.filter { lanes[$0] == commit.sha }
            let commitLane: Int
            if let primary = allMatches.first {
                commitLane = primary
            } else {
                if let nilIndex = lanes.firstIndex(where: { $0 == nil }) {
                    lanes[nilIndex] = commit.sha
                    commitLane = nilIndex
                } else {
                    lanes.append(commit.sha)
                    commitLane = lanes.count - 1
                }
            }

            let activeAtTop = lanes.enumerated().compactMap { index, value in
                value != nil ? index : nil
            }
            let mergesIn = allMatches.filter { $0 != commitLane }
            for index in mergesIn { lanes[index] = nil }

            let firstParent = commit.parentShas.first
            lanes[commitLane] = firstParent

            var mergesOut: [Int] = []
            for parent in commit.parentShas.dropFirst() {
                if let existing = lanes.firstIndex(where: { $0 == parent }) {
                    mergesOut.append(existing)
                } else if let nilIndex = lanes.firstIndex(where: { $0 == nil }) {
                    lanes[nilIndex] = parent
                    mergesOut.append(nilIndex)
                } else {
                    lanes.append(parent)
                    mergesOut.append(lanes.count - 1)
                }
            }

            while lanes.last == nil { lanes.removeLast() }

            let activeAtBottom = lanes.enumerated().compactMap { index, value in
                value != nil ? index : nil
            }

            let topMax = activeAtTop.last ?? 0
            let bottomMax = activeAtBottom.last ?? 0
            let mergesMax = max(mergesIn.last ?? 0, mergesOut.last ?? 0)
            let rowTotal = max(commitLane, topMax, bottomMax, mergesMax) + 1
            maxLanes = max(maxLanes, rowTotal)

            rows.append(GraphRowLayout(
                commitLane: commitLane,
                activeLanesAtTop: activeAtTop,
                activeLanesAtBottom: activeAtBottom,
                mergesIn: mergesIn,
                mergesOut: mergesOut,
                totalLanes: rowTotal,
                isMerge: commit.parentShas.count > 1
            ))
        }

        return (rows, maxLanes)
    }
}
