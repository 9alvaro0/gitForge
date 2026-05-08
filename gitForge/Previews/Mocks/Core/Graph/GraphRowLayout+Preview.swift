import Foundation

extension Array where Element == GraphRowLayout {
    /// Small linear/branched/merged sample for graph previews.
    static var previewSamples: [GraphRowLayout] {
        [
            GraphRowLayout(
                commitLane: 0, commitBranchId: 0,
                lanesAtTop: [],
                lanesAtBottom: [LaneOccupation(lane: 0, branchId: 0), LaneOccupation(lane: 1, branchId: 1)],
                mergesIn: [],
                mergesOut: [LaneOccupation(lane: 1, branchId: 1)],
                totalLanes: 2, isMerge: false
            ),
            GraphRowLayout(
                commitLane: 0, commitBranchId: 0,
                lanesAtTop: [LaneOccupation(lane: 0, branchId: 0), LaneOccupation(lane: 1, branchId: 1)],
                lanesAtBottom: [LaneOccupation(lane: 0, branchId: 0), LaneOccupation(lane: 1, branchId: 1)],
                mergesIn: [], mergesOut: [],
                totalLanes: 2, isMerge: false
            ),
            GraphRowLayout(
                commitLane: 0, commitBranchId: 0,
                lanesAtTop: [LaneOccupation(lane: 0, branchId: 0), LaneOccupation(lane: 1, branchId: 1)],
                lanesAtBottom: [LaneOccupation(lane: 0, branchId: 0)],
                mergesIn: [LaneOccupation(lane: 1, branchId: 1)],
                mergesOut: [],
                totalLanes: 2, isMerge: true
            ),
            GraphRowLayout(
                commitLane: 0, commitBranchId: 0,
                lanesAtTop: [LaneOccupation(lane: 0, branchId: 0)],
                lanesAtBottom: [],
                mergesIn: [], mergesOut: [],
                totalLanes: 1, isMerge: false
            ),
        ]
    }
}
