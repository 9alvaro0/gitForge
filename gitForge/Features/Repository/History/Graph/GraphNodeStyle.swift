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

    /// A stash keeps its square even at HEAD; otherwise HEAD wins over merge.
    static func `for`(_ row: GraphRow, isHeadCommit: Bool) -> GraphNodeStyle {
        switch row.node.kind {
        case .stash: .stash
        case _ where isHeadCommit: .head
        case .merge: .merge
        case .commit: .commit
        }
    }
}
