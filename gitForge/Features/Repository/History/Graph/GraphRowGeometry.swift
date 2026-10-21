import SwiftUI

/// One half of a step, as a row draws it.
nonisolated enum GraphSegment: Equatable, Sendable {
    /// A half of a step that stays in its column.
    case line(from: CGPoint, to: CGPoint)
    /// A half of the S of a step that changes column (`GraphCurve`).
    case curve(start: CGPoint, control1: CGPoint, control2: CGPoint, end: CGPoint)

    var path: Path {
        var path = Path()
        switch self {
        case let .line(from, to):
            path.move(to: from)
            path.addLine(to: to)
        case let .curve(start, control1, control2, end):
            path.move(to: start)
            path.addCurve(to: end, control1: control1, control2: control2)
        }
        return path
    }
}

/// Where a row draws its halves of the steps that cross it (§5.1), as plain
/// geometry.
///
/// Rows sit one pitch apart: the row height plus the gap the table leaves
/// between rows. A step runs from one row centre to the next, one pitch
/// below, and its two halves join in the middle of the gap (the joint): the
/// row draws the arriving half of each `stepsAbove` (joint above to centre)
/// and the leaving half of each `stepsBelow` (centre to joint below).
///
/// The canvas is centred on its row, so its centre is the row's centre, and
/// reaches `bleed` past each joint, so no stroke that ends at or past a
/// joint is cut by the canvas edge. A straight half ends flat on its joint,
/// where the neighbour's half of the same line starts. A curve half runs
/// `overlap` past its joint along the same S (`GraphCurve`): a curve's end
/// is slanted, so two halves that only touched there would show a faint
/// antialiased seam along it; overlapping, each row draws the whole joint
/// itself, even under a neighbour's selection or hover background. The overlap is the same curve in the same colour, so it can't
/// be seen while the rows are opaque (`overlapsJoints`).
///
/// A dashed step (`isDashed`) has no overlap: two translucent strokes laid
/// over each other draw a darker band, and a dash pattern drawn twice over the
/// same stretch no longer reads as one. Its halves stop exactly on the joint
/// instead, and each starts its dash where the other left it (`dashPhase`),
/// so the pattern runs unbroken from one row to the next.
nonisolated struct GraphRowGeometry {
    let style: GraphStyle
    /// The canvas: the gutter's width, one row pitch plus `bleed` above and below.
    let size: CGSize
    /// Whether the curve halves overlap their neighbours' past the joints.
    /// Off for a row drawn translucent (dimmed): two translucent rows would
    /// show their overlap twice as strong, so its halves stop exactly on the
    /// joint, where the halves of an S meet with the same tangent.
    var overlapsJoints = true

    /// How far a curve half runs past its joint, measured down the S: half
    /// the edge stroke. Along the slanted S that is at least as far. The part
    /// of the S a row leaves to its neighbour then lies, stroke and all, on
    /// the neighbour's side of the joint (a stroke reaches at most half its
    /// width up or down), so each row draws every point of the S on its own
    /// side.
    static func overlap(for metrics: GraphMetrics) -> CGFloat {
        metrics.edgeWidth / 2
    }

    /// Room past each joint for the overlap, half the stroke around its end
    /// and `antialiasMargin`, rounded up to a whole point so the canvas edge
    /// keeps the pixel alignment it has without the bleed. Edges are the only
    /// strokes that reach the joints; nodes and their rings sit around the
    /// centre.
    static func bleed(for metrics: GraphMetrics) -> CGFloat {
        (overlap(for: metrics) + metrics.edgeWidth / 2 + antialiasMargin).rounded(.up)
    }

    /// Room for the antialiased fringe of a stroke.
    static let antialiasMargin: CGFloat = 0.5

    /// The canvas height for rows `pitch` apart.
    static func canvasHeight(pitch: CGFloat, metrics: GraphMetrics) -> CGFloat {
        pitch + 2 * bleed(for: metrics)
    }

    /// The period of the 2-part dash (a dash and a gap of half a period each)
    /// for rows `pitch` apart: the one nearest to 6 pt, a 3–3 dash, that
    /// still fits a whole number of times in half a pitch. A half of a
    /// straight step is that long, so the pattern runs through it and ends
    /// complete on the joint, ready for the next row to start it again. 7.25
    /// for the regular density (pitch 29), 5.75 for the compact one (23).
    static func dashPeriod(pitch: CGFloat) -> CGFloat {
        let half = pitch / 2
        return half / max(1, (half / 6).rounded())
    }

    /// Whether a step is drawn dashed: a stash's side step and a ghost line.
    static func isDashed(_ step: GraphStep) -> Bool {
        switch step.stroke {
        case .solid: false
        case .ghost, .stash: true
        }
    }

    var bleed: CGFloat { Self.bleed(for: style.metrics) }
    /// `dashPeriod(pitch:)` for this geometry's rows.
    var dashPeriod: CGFloat { Self.dashPeriod(pitch: pitch) }
    var center: CGFloat { size.height / 2 }
    /// Distance between row centres.
    var pitch: CGFloat { size.height - 2 * bleed }
    /// The middle of the gap above the row, where the arriving halves join.
    var jointAbove: CGFloat { bleed }
    /// The middle of the gap below the row, where the leaving halves join.
    var jointBelow: CGFloat { size.height - bleed }

    /// Calls `body` with each half, its step and the dash phase the half starts
    /// with, in drawing order: every curve first, then the straight halves, so
    /// a line passing through stays on top of the curves that cross it (§5.2).
    /// Allocates nothing.
    ///
    /// The phase is how far into the dash pattern (`dashPeriod`) the half's
    /// start lies, as `StrokeStyle.dashPhase` takes it; 0 for a solid half,
    /// which has no pattern. A dashed half that leaves the row, or a straight
    /// one that arrives, starts at 0: a straight half is half a pitch long, a
    /// whole number of periods, so the one above ends its pattern complete.
    /// A dashed curve that arrives carries on where the half of the row above
    /// stopped. That one, the mirror of this half, is as long, so the pattern
    /// ends at its length modulo the period. At the row's centre the pattern
    /// starts over, which nobody sees under the node.
    func forEachSegment(of row: GraphRow, _ body: (GraphSegment, GraphStep, _ dashPhase: CGFloat) -> Void) {
        let solidOverlap = overlapsJoints ? Self.overlap(for: style.metrics) : 0
        let period = dashPeriod
        for step in row.stepsAbove where step.from != step.to {
            let dashed = Self.isDashed(step)
            let arriving = GraphCurve.arriving(fromX: style.laneCenter(step.from), toX: style.laneCenter(step.to),
                                               center: center, height: pitch, overlap: dashed ? 0 : solidOverlap)
            let phase = dashed ? GraphCurve.arcLength(arriving).truncatingRemainder(dividingBy: period) : 0
            body(curve(arriving), step, phase)
        }
        for step in row.stepsBelow where step.from != step.to {
            let leaving = GraphCurve.leaving(fromX: style.laneCenter(step.from), toX: style.laneCenter(step.to),
                                             center: center, height: pitch,
                                             overlap: Self.isDashed(step) ? 0 : solidOverlap)
            body(curve(leaving), step, 0)
        }
        for step in row.stepsAbove where step.from == step.to {
            let x = style.laneCenter(step.to)
            body(.line(from: CGPoint(x: x, y: jointAbove), to: CGPoint(x: x, y: center)), step, 0)
        }
        for step in row.stepsBelow where step.from == step.to {
            let x = style.laneCenter(step.from)
            body(.line(from: CGPoint(x: x, y: center), to: CGPoint(x: x, y: jointBelow)), step, 0)
        }
    }

    private func curve(_ bezier: GraphCurve.Bezier) -> GraphSegment {
        .curve(start: bezier.start, control1: bezier.control1, control2: bezier.control2, end: bezier.end)
    }
}
