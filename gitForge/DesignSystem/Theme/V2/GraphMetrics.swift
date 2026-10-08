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
    let headOuterRadius: CGFloat
    let headInnerRadius: CGFloat
    /// Dashed square, corner radius 2.
    let stashSize: CGFloat
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
        headOuterRadius: 7.5, headInnerRadius: 3.5, stashSize: 9, worktreeRadius: 4.5,
        selectHaloOutset: 5.5, selectHaloOpacity: 0.30,
        hoverRingOutset: 3.5, hoverRingWidth: 1.5, hoverRingOpacity: 0.75,
        chipHeight: 18
    )

    static let compact = GraphMetrics(
        laneWidth: 12, firstLaneX: 12, edgeWidth: 1.75, nodeRadius: 3.75, nodeGap: 2,
        headOuterRadius: 6.75, headInnerRadius: 2.75, stashSize: 7.5, worktreeRadius: 3.75,
        selectHaloOutset: 5.5, selectHaloOpacity: 0.30,
        hoverRingOutset: 3.5, hoverRingWidth: 1.5, hoverRingOpacity: 0.75,
        chipHeight: 16
    )
}
