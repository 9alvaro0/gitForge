import Foundation

/// The colour a line, a node or a step is drawn with. The view maps each role
/// to a theme colour; the engine only decides which role goes where.
nonisolated enum GraphColorRole: Sendable, Hashable {
    /// The user's accent: HEAD's line.
    case head
    /// The main trunk (`main`, `master`, `trunk`).
    case main
    /// The develop trunk (`develop`, `dev`).
    case develop
    case stash
    /// Nothing owns it, such as the track of a parent that is not loaded.
    case neutral
    /// Index into the palette for the current accent.
    case pool(Int)
}

/// How a step is drawn.
nonisolated enum GraphStroke: Sendable, Hashable {
    case solid
    /// The child commit of the edge it draws exists only on the server (§4.3).
    case ghost
    /// The side step from a stash into its commit.
    case stash
    /// The connector from the Uncommitted changes row down to HEAD's commit (§3.5).
    case uncommitted
}

/// Centre of one row to the centre of the next: straight when `from == to`,
/// an S curve otherwise. The upper row draws its top half, the lower row its
/// bottom half (§5.1).
nonisolated struct GraphStep: Sendable, Hashable {
    let from: Int
    let to: Int
    let color: GraphColorRole
    let stroke: GraphStroke
}

nonisolated extension GraphStep {
    /// The connector's step, the same on every boundary it crosses: column 0, HEAD's colour.
    static let uncommitted = GraphStep(from: 0, to: 0, color: .head, stroke: .uncommitted)
}

nonisolated struct GraphNode: Sendable, Hashable {
    nonisolated enum Kind: Sendable, Hashable {
        case commit
        case merge
        case stash
    }

    let column: Int
    let kind: Kind
    let color: GraphColorRole
    let isGhost: Bool
}

/// What one row of the graph draws.
nonisolated struct GraphRow: Sendable, Hashable {
    let node: GraphNode
    /// Drawn from the row's top edge to its centre: the previous row's `stepsBelow`.
    /// On the first row, the connector arriving from the Uncommitted changes row, if any.
    let stepsAbove: [GraphStep]
    /// Drawn from the centre to the bottom edge, sorted by `(from, to)`.
    let stepsBelow: [GraphStep]
    /// Columns this row uses: one past the rightmost column of its node and its steps.
    let width: Int

    static let empty = GraphRow(node: GraphNode(column: 0, kind: .commit, color: .neutral, isGhost: false),
                                stepsAbove: [], stepsBelow: [], width: 1)
}

/// The whole graph: one row per commit, in the order of `GraphInput.commits`.
nonisolated struct GraphLayout: Sendable, Equatable {
    let rows: [GraphRow]
    /// Columns the layout takes up, at least 1. It counts every column assigned,
    /// including those reserved for HEAD and the trunks (§3.9), which may hold no
    /// drawn line on some rows or even on all of them, so it can be wider than the
    /// widest row.
    let columnCount: Int
    /// The connector's step when the layout draws it (`GraphInput.drawsUncommittedConnector`):
    /// the Uncommitted changes row draws its leaving half (§5.5), and the first row's
    /// `stepsAbove` holds it. Nil otherwise.
    var uncommitted: GraphStep? = nil

    static let empty = GraphLayout(rows: [], columnCount: 1)
}
