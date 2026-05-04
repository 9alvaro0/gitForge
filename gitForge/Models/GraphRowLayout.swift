import Foundation

nonisolated struct GraphRowLayout: Sendable, Equatable, Hashable {
    let commitLane: Int
    /// Lanes occupying a slot at the start of the row (drawn from row top to row center).
    let activeLanesAtTop: [Int]
    /// Lanes occupying a slot at the end of the row (drawn from row center to row bottom).
    let activeLanesAtBottom: [Int]
    /// Other lanes that pointed at this commit and merge into `commitLane` at the row center.
    let mergesIn: [Int]
    /// Lanes branching out of this commit toward additional parents (anything past first parent).
    let mergesOut: [Int]
    /// Total lane count to draw (used for width). Includes the commit lane and any active/merge lane.
    let totalLanes: Int
    let isMerge: Bool

    static let empty = GraphRowLayout(
        commitLane: 0,
        activeLanesAtTop: [],
        activeLanesAtBottom: [],
        mergesIn: [],
        mergesOut: [],
        totalLanes: 1,
        isMerge: false
    )
}
