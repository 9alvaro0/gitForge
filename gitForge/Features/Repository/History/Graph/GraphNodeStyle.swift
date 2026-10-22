import Foundation

/// How a commit's node is drawn (redesign spec §4.5): node shape encodes
/// kind, so lane colour never carries meaning alone.
nonisolated enum GraphNodeStyle: Equatable, Sendable {
    /// Filled dot.
    case commit
    /// Hollow ring.
    case merge
    /// Outer ring with an inner dot.
    case head
    /// Dashed square.
    case stash
    /// Hollow dashed ring: a commit that only exists on the server (§4.3),
    /// merge or not.
    case ghost

    /// A stash keeps its square even at HEAD; otherwise HEAD wins, then a
    /// ghost, then a merge.
    static func `for`(_ row: GraphRow, isHeadCommit: Bool) -> GraphNodeStyle {
        switch row.node.kind {
        case .stash: .stash
        case _ where isHeadCommit: .head
        case _ where row.node.isGhost: .ghost
        case .merge: .merge
        case .commit: .commit
        }
    }
}
