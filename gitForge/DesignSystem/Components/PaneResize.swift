import CoreGraphics

/// What dragging a pane's divider does to the pane, like `NSSplitView`:
/// within its bounds the pane takes the proposed size; pulled past its
/// collapse point it collapses. `ColumnDragHandle` and `RowDragHandle` use it.
nonisolated enum PaneResize: Equatable {
    case size(CGFloat)
    case collapse

    /// The pane for a drag that proposes `proposed`. Without `collapseBelow`
    /// it never collapses and stays at `min` at least. `min` wins when the
    /// bounds cross (a cap that shrank below the pane's minimum).
    static func resolve(proposed: CGFloat, min lower: CGFloat, max upper: CGFloat,
                        collapseBelow: CGFloat? = nil) -> PaneResize {
        if let collapseBelow, proposed < collapseBelow { return .collapse }
        return .size(Swift.max(lower, Swift.min(proposed, upper)))
    }

    /// `NSSplitView`'s point: a pane collapses once dragged under half its
    /// minimum.
    static func collapseThreshold(min: CGFloat) -> CGFloat {
        min / 2
    }
}
