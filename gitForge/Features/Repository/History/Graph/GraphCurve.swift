import CoreGraphics
import Foundation

/// The S a step draws when it changes column (§5.1), and the pieces of it the
/// two rows it crosses draw. The full S runs from one row centre `(x0, y0)`
/// to the next, `(x1, y0 + h)`, where `h` is the row pitch (the row height
/// plus the gap between rows), with controls `(x0, y0 + h/2)` and
/// `(x1, y0 + h/2)`. Its middle, `t = 0.5`, lies in the middle of the gap
/// between the rows, halfway across: the row above draws the S from its
/// centre to there (`leaving`), the row below from there to its centre
/// (`arriving`).
///
/// With an `overlap` each half runs that far past the middle, measured
/// vertically, as an exact piece of the same S (`piece(of:from:to:)`), so
/// the two halves overlap along one curve instead of only touching. With no
/// overlap they are the exact split at `t = 0.5`: they meet at the same
/// point with the same tangent.
///
/// `nonisolated` because the `Canvas` renderer runs off the main actor.
nonisolated enum GraphCurve {
    typealias Bezier = (start: CGPoint, control1: CGPoint, control2: CGPoint, end: CGPoint)

    /// The whole S of a step from `(x0, top)` to `(x1, top + height)`.
    static func step(fromX x0: CGFloat, toX x1: CGFloat, top: CGFloat, height: CGFloat) -> Bezier {
        (start: CGPoint(x: x0, y: top),
         control1: CGPoint(x: x0, y: top + height / 2),
         control2: CGPoint(x: x1, y: top + height / 2),
         end: CGPoint(x: x1, y: top + height))
    }

    /// The half of the S drawn by the upper row: from its centre `(x0, center)`
    /// to the middle of the gap below it, `((x0 + x1) / 2, center + height / 2)`,
    /// and `overlap` further down along the S. `height` is the row pitch.
    static func leaving(fromX x0: CGFloat, toX x1: CGFloat, center: CGFloat, height: CGFloat,
                        overlap: CGFloat = 0) -> Bezier {
        let s = step(fromX: x0, toX: x1, top: center, height: height)
        return piece(of: s, from: 0, to: 0.5 + parameter(pastMiddleBy: overlap, height: height))
    }

    /// The half of the S drawn by the lower row: from `overlap` above the middle
    /// of the gap above it, `((x0 + x1) / 2, center - height / 2)`, along the S
    /// to its centre `(x1, center)`. `height` is the row pitch.
    static func arriving(fromX x0: CGFloat, toX x1: CGFloat, center: CGFloat, height: CGFloat,
                         overlap: CGFloat = 0) -> Bezier {
        let s = step(fromX: x0, toX: x1, top: center - height, height: height)
        return piece(of: s, from: 0.5 - parameter(pastMiddleBy: overlap, height: height), to: 1)
    }

    /// How far past its middle, in `t`, an S `height` tall lies `overlap`
    /// below (or, by symmetry, above) its middle. The S's height is
    /// `y(1/2 + s) - y(1/2) = height · (3s/4 + s³)` whatever its columns, and
    /// with `s = sinh θ` that is `height · sinh(3θ) / 4`, so
    /// `s = sinh(asinh(4 · overlap / height) / 3)`. Zero for no overlap.
    static func parameter(pastMiddleBy overlap: CGFloat, height: CGFloat) -> CGFloat {
        guard overlap != 0 else { return 0 }
        return sinh(asinh(4 * overlap / height) / 3)
    }

    /// The exact piece of `curve` between `t0` and `t1`, as a cubic of its
    /// own: drawn whole, it traces `curve` from `t0` to `t1`. Its control
    /// points are the curve's blossom at `(t0, t0, t0)`, `(t0, t0, t1)`,
    /// `(t0, t1, t1)` and `(t1, t1, t1)`.
    static func piece(of curve: Bezier, from t0: CGFloat, to t1: CGFloat) -> Bezier {
        (start: blossom(curve, t0, t0, t0),
         control1: blossom(curve, t0, t0, t1),
         control2: blossom(curve, t0, t1, t1),
         end: blossom(curve, t1, t1, t1))
    }

    /// The point of `curve` at `t`.
    static func point(on curve: Bezier, at t: CGFloat) -> CGPoint {
        blossom(curve, t, t, t)
    }

    /// De Casteljau with a different parameter at each level.
    private static func blossom(_ c: Bezier, _ u: CGFloat, _ v: CGFloat, _ w: CGFloat) -> CGPoint {
        let a = lerp(c.start, c.control1, u), b = lerp(c.control1, c.control2, u), d = lerp(c.control2, c.end, u)
        return lerp(lerp(a, b, v), lerp(b, d, v), w)
    }

    /// Exact at both ends: `t = 0` gives `p`, `t = 1` gives `q`.
    private static func lerp(_ p: CGPoint, _ q: CGPoint, _ t: CGFloat) -> CGPoint {
        CGPoint(x: (1 - t) * p.x + t * q.x, y: (1 - t) * p.y + t * q.y)
    }
}
