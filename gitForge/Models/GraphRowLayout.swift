import Foundation

/// Slot occupied by a logical branch in a particular column at a row boundary.
nonisolated struct LaneOccupation: Sendable, Equatable, Hashable {
    let lane: Int
    let branchId: Int
}

nonisolated struct GraphRowLayout: Sendable, Equatable, Hashable {
    let commitLane: Int
    let commitBranchId: Int
    /// Lanes occupying a slot at the start of the row (drawn from row top to row center).
    let lanesAtTop: [LaneOccupation]
    /// Lanes occupying a slot at the end of the row (drawn from row center to row bottom).
    let lanesAtBottom: [LaneOccupation]
    /// Other lanes (above) merging into `commitLane` at the row center.
    let mergesIn: [LaneOccupation]
    /// Lanes branching out of this commit (below) toward additional parents.
    let mergesOut: [LaneOccupation]
    /// Total lane count to draw (used for width).
    let totalLanes: Int
    let isMerge: Bool

    static let empty = GraphRowLayout(
        commitLane: 0,
        commitBranchId: 0,
        lanesAtTop: [],
        lanesAtBottom: [],
        mergesIn: [],
        mergesOut: [],
        totalLanes: 1,
        isMerge: false
    )
}
