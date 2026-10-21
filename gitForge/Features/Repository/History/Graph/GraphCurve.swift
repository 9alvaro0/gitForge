import CoreGraphics

/// Control points for the two halves of the S a step draws when it changes
/// column (§5.1). The full S runs from one row centre `(x0, y0)` to the next,
/// `(x1, y0 + h)`, where `h` is the row pitch (the row height plus the gap
/// between rows), with controls `(x0, y0 + h/2)` and `(x1, y0 + h/2)`. It is
/// split at `t = 0.5` so the row above and the row below each draw their own
/// half, and the two meet in the middle of the gap between the rows, halfway
/// across, with the same tangent.
///
/// `nonisolated` because the `Canvas` renderer runs off the main actor.
nonisolated enum GraphCurve {
    typealias Bezier = (start: CGPoint, control1: CGPoint, control2: CGPoint, end: CGPoint)

    /// Half of the S drawn by the upper row: its centre `(x0, center)` to the
    /// middle of the gap below it, `((x0 + x1) / 2, center + height / 2)`.
    /// `height` is the row pitch.
    static func leaving(fromX x0: CGFloat, toX x1: CGFloat, center: CGFloat, height: CGFloat) -> Bezier {
        (start: CGPoint(x: x0, y: center),
         control1: CGPoint(x: x0, y: center + height / 4),
         control2: CGPoint(x: (3 * x0 + x1) / 4, y: center + 3 * height / 8),
         end: CGPoint(x: (x0 + x1) / 2, y: center + height / 2))
    }

    /// Half of the S drawn by the lower row: the middle of the gap above it,
    /// `((x0 + x1) / 2, center - height / 2)`, to its centre `(x1, center)`.
    /// `height` is the row pitch.
    static func arriving(fromX x0: CGFloat, toX x1: CGFloat, center: CGFloat, height: CGFloat) -> Bezier {
        (start: CGPoint(x: (x0 + x1) / 2, y: center - height / 2),
         control1: CGPoint(x: (x0 + 3 * x1) / 4, y: center - 3 * height / 8),
         control2: CGPoint(x: x1, y: center - height / 4),
         end: CGPoint(x: x1, y: center))
    }
}
