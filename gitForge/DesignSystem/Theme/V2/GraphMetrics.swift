import CoreGraphics

/// Commit graph geometry per density (redesign spec §4.5). `nonisolated`
/// for the off-main-actor `Canvas` renderer.
nonisolated struct GraphMetrics: Equatable, Sendable {
    /// Distance between lane centres.
    let laneWidth: CGFloat
    /// Lane 0 centre from the column edge.
    let firstLaneX: CGFloat
    let edgeWidth: CGFloat
    /// Commit node (filled) and merge node (hollow ring).
    let nodeRadius: CGFloat
    /// Ring in bg.content separating a node from its edges.
    let nodeGap: CGFloat
    /// Width of the band beside each edge, on both sides, where a line drawn
    /// earlier in the row shows the row's background instead: where a line
    /// passes over another, the one underneath opens a gap (graph v3 spec
    /// §5.2). 0 draws no band.
    let crossingGap: CGFloat
    /// Radius around the points where lines meet (the row's commit, and where
    /// a curve joins a line passing through the row's centre) inside which the
    /// crossing band leaves lines alone, so they join cleanly.
    let crossingNodeClearance: CGFloat
    let headOuterRadius: CGFloat
    let headInnerRadius: CGFloat
    /// Dashed square, corner radius `squareMarkRadius`.
    let stashSize: CGFloat
    /// Corner of the square marks: stash nodes and the uncommitted row.
    static let squareMarkRadius: CGFloat = 2
    /// Hollow dashed circle.
    let worktreeRadius: CGFloat
    let selectHaloOutset: CGFloat
    let selectHaloOpacity: Double
    let hoverRingOutset: CGFloat
    let hoverRingWidth: CGFloat
    let hoverRingOpacity: Double
    /// Ref chips in the description column.
    let chipHeight: CGFloat

    static let regular = GraphMetrics(
        laneWidth: 14, firstLaneX: 14, edgeWidth: 2, nodeRadius: 4.5, nodeGap: 2,
        crossingGap: 1.5, crossingNodeClearance: 12,
        headOuterRadius: 7.5, headInnerRadius: 3.5, stashSize: 9, worktreeRadius: 4.5,
        selectHaloOutset: 5.5, selectHaloOpacity: 0.30,
        hoverRingOutset: 3.5, hoverRingWidth: 1.5, hoverRingOpacity: 0.75,
        chipHeight: 18
    )

    static let compact = GraphMetrics(
        laneWidth: 12, firstLaneX: 12, edgeWidth: 1.75, nodeRadius: 3.75, nodeGap: 2,
        crossingGap: 1.5, crossingNodeClearance: 10,
        headOuterRadius: 6.75, headInnerRadius: 2.75, stashSize: 7.5, worktreeRadius: 3.75,
        selectHaloOutset: 5.5, selectHaloOpacity: 0.30,
        hoverRingOutset: 3.5, hoverRingWidth: 1.5, hoverRingOpacity: 0.75,
        chipHeight: 16
    )
}
