import SwiftUI

/// One half of a step as a row draws it, or two halves of one line drawn as
/// one path.
nonisolated enum GraphSegment: Equatable, Sendable {
    /// A half of a step that stays in its column.
    case line(from: CGPoint, to: CGPoint)
    /// A half of the S of a step that changes column (`GraphCurve`).
    case curve(start: CGPoint, control1: CGPoint, control2: CGPoint, end: CGPoint)
    /// The half of a line that arrives at the row's centre and the half that
    /// leaves it, where they meet away from the node: each exactly as it
    /// would be drawn alone, the second carrying on from the end of the
    /// first, so the line has no break where they meet
    /// (`GraphRowGeometry.forEachSegment`).
    case joined(Piece, Piece)

    /// A half drawn as part of a `joined` segment, with the shapes of a half
    /// drawn alone. Its own type rather than a nested `GraphSegment`, which
    /// would put each pair in a heap box.
    nonisolated enum Piece: Equatable, Sendable {
        case line(from: CGPoint, to: CGPoint)
        case curve(start: CGPoint, control1: CGPoint, control2: CGPoint, end: CGPoint)

        var start: CGPoint {
            switch self {
            case let .line(from, _): from
            case let .curve(start, _, _, _): start
            }
        }

        /// Its length along the path: a line's, or a curve's arc length
        /// (`GraphCurve.arcLength`).
        var length: CGFloat {
            switch self {
            case let .line(from, to): hypot(to.x - from.x, to.y - from.y)
            case let .curve(start, control1, control2, end):
                GraphCurve.arcLength((start: start, control1: control1, control2: control2, end: end))
            }
        }

        /// The piece drawn alone.
        var alone: GraphSegment {
            switch self {
            case let .line(from, to): .line(from: from, to: to)
            case let .curve(start, control1, control2, end):
                .curve(start: start, control1: control1, control2: control2, end: end)
            }
        }

        /// Adds the piece to `path`, from the path's current point on.
        func extend(_ path: inout Path) {
            switch self {
            case let .line(_, to): path.addLine(to: to)
            case let .curve(_, control1, control2, end): path.addCurve(to: end, control1: control1, control2: control2)
            }
        }
    }

    /// One subpath: a `joined` segment's second piece starts where the first
    /// ends, so it carries on from there instead of moving to its own start.
    ///
    /// Two straight pieces, one above the other, make a single line from the
    /// first one's start to the second one's end. CoreGraphics strokes a path
    /// of exactly one line with the exact coverage of each pixel, and any
    /// other path with its general rasterizer, which lights a partly covered
    /// pixel differently (at 1x, the compact line's edge pixels, 7/8 covered,
    /// come out about 8 % brighter). As one line, a line passing straight
    /// through the row looks just like the straight halves drawn alone around
    /// it, in the rows of its commits.
    var path: Path {
        var path = Path()
        switch self {
        case let .line(from, to), let .joined(.line(from, _), .line(_, to)):
            path.move(to: from)
            path.addLine(to: to)
        case let .curve(start, control1, control2, end):
            path.move(to: start)
            path.addCurve(to: end, control1: control1, control2: control2)
        case let .joined(arriving, leaving):
            path.move(to: arriving.start)
            arriving.extend(&path)
            leaving.extend(&path)
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
/// joint is cut by the canvas edge, nor the crossing band around it (§5.2).
/// A curve half runs `overlap` past its joint along the same S
/// (`GraphCurve`): a curve's end is slanted, so two halves that only touched
/// there would show a faint antialiased seam along it; overlapping, each row
/// draws the whole joint itself, even under a neighbour's selection or hover
/// background. A straight half runs `straightOverlap` past its joint, so a
/// line passing over a crossing right on the joint stays on top on both
/// sides of it. An overlap is the same line in the same colour, so it can't
/// be seen while the rows are opaque (`overlapsJoints`).
///
/// Where a solid line arrives at the row's centre and carries on from it
/// away from the node, straight or bending, the row draws its two halves as
/// one path, so nothing breaks where they meet (`forEachSegment`).
///
/// A dashed step (`isDashed`) has no overlap: two translucent strokes laid
/// over each other draw a darker band, and a dash pattern drawn twice over the
/// same stretch no longer reads as one. Its halves stop exactly on the joint
/// instead. Each holds a whole number of its dash period (`dashPeriod`, or
/// `dashPeriod(ofCurve:)` for an S), so it starts with a dash and ends with
/// a complete gap, and the pattern runs unbroken from one half to the next,
/// across a joint or the row's centre, with nothing carried between rows.
nonisolated struct GraphRowGeometry {
    let style: GraphStyle
    /// The canvas: the gutter's width, one row pitch plus `bleed` above and below.
    let size: CGSize
    /// Whether the solid halves overlap their neighbours' past the joints.
    /// Off for a row drawn translucent (dimmed): two translucent rows would
    /// show their overlap twice as strong, so its halves stop exactly on the
    /// joint, where the halves of an S meet with the same tangent.
    var overlapsJoints = true
    /// The gap the table leaves between rows (`HistoryTableLayout.rowSpacing`):
    /// the pitch less the row's own height. 0 for rows that touch.
    var rowSpacing: CGFloat = 0

    /// How far a curve half runs past its joint, measured down the S: half
    /// the edge stroke. Along the slanted S that is at least as far. The part
    /// of the S a row leaves to its neighbour then lies, stroke and all, on
    /// the neighbour's side of the joint (a stroke reaches at most half its
    /// width up or down), so each row draws every point of the S on its own
    /// side.
    static func overlap(for metrics: GraphMetrics) -> CGFloat {
        metrics.edgeWidth / 2
    }

    /// How far a solid straight half runs past its joint: as far as a curve
    /// half's stroke can reach past it. A curve half runs `overlap` past the
    /// joint, measured down the S, but its butt end is slanted, so a corner of
    /// its stroke reaches up to half the stroke further. Each row can only
    /// erase what it drew itself, so where an S crosses a straight right on
    /// the joint, the straight's band (§5.2) has to run past that corner, or
    /// a sliver of the curve shows in the gap on the neighbour's side.
    static func straightOverlap(for metrics: GraphMetrics) -> CGFloat {
        overlap(for: metrics) + metrics.edgeWidth / 2
    }

    /// Room past each joint for a curve half's overlap, the stroke and the
    /// crossing band around its end, and `antialiasMargin`, rounded up to a
    /// whole point so the canvas edge keeps the pixel alignment it has without
    /// the bleed. A straight's end is flat, so it reaches only its own
    /// overlap. Edges are the only strokes that reach the joints; nodes and
    /// their rings sit around the centre.
    static func bleed(for metrics: GraphMetrics) -> CGFloat {
        (overlap(for: metrics) + metrics.edgeWidth / 2 + metrics.crossingGap + antialiasMargin).rounded(.up)
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
    /// `dashPeriod(pitch:)` for this geometry's rows: the period of a dashed
    /// straight half.
    var dashPeriod: CGFloat { Self.dashPeriod(pitch: pitch) }

    /// The dash period of a dashed S half `length` long (its arc length): the
    /// one that fits a whole number of times in it nearest to the straight
    /// half's (`dashPeriod`). For the S of one to twenty columns it is at most
    /// 17 % longer (one column, compact density) or 9 % shorter. Both halves
    /// of an S are as long, so they have the same period.
    func dashPeriod(ofCurve length: CGFloat) -> CGFloat {
        length / max(1, (length / dashPeriod).rounded())
    }

    var center: CGFloat { size.height / 2 }
    /// Distance between row centres.
    var pitch: CGFloat { size.height - 2 * bleed }
    /// The row's own height: the pitch less the gap the table leaves between rows.
    var rowHeight: CGFloat { pitch - rowSpacing }
    /// The middle of the gap above the row, where the arriving halves join.
    var jointAbove: CGFloat { bleed }
    /// The middle of the gap below the row, where the leaving halves join.
    var jointBelow: CGFloat { size.height - bleed }

    /// The outer radius of the selection halo around a node whose own outer
    /// radius is `outer`: the node's outset (`selectHaloOutset`), but never
    /// past the row's edge (half its height), which a halo would otherwise
    /// cross into the gap and the next row, or get clipped by (§5.3). The
    /// regular density's halo fits; the compact one's, around a HEAD, is held
    /// to 11 pt instead of 12.25.
    func haloRadius(outer: CGFloat) -> CGFloat {
        min(outer + style.metrics.selectHaloOutset, rowHeight / 2)
    }

    /// The radius of the path the hover ring is stroked along around a node
    /// whose outer radius is `outer`: the node's outset (`hoverRingOutset`),
    /// but held back far enough that the stroke, which reaches half its width
    /// past the path, stays inside the row too (§5.3).
    func hoverRingRadius(outer: CGFloat) -> CGFloat {
        let metrics = style.metrics
        return min(outer + metrics.hoverRingOutset, rowHeight / 2 - metrics.hoverRingWidth / 2)
    }

    /// Calls `body` with each segment the row draws, its step and its dash
    /// period, in drawing order (§5.2): first the S halves drawn alone, then
    /// the lines joined with an S, then the straight halves drawn alone and
    /// the lines joined straight. So a straight passing through stays on top
    /// of every S that crosses it, and an S drawn as part of a joined line
    /// still opens a gap where a later straight crosses it. Allocates
    /// nothing.
    ///
    /// Where a line arrives at the row's centre and carries on from it away
    /// from the node, its two halves are one segment, `.joined`, reported
    /// once with the arriving half's step (`joinedPair(at:in:)`). Drawn as
    /// two, each would end flat on the centre, and where the centre falls in
    /// the middle of a pixel, as it does on a 1x screen, each covers only half
    /// of that pixel row: the line would show a faint notch on every row it
    /// passes. Under the node the notch is covered.
    ///
    /// The dash period is the length of a dash and the gap after it, half
    /// each, for a dashed half; 0 for a solid segment, which has none. A
    /// dashed straight half, half a pitch long, has `dashPeriod`; a dashed S
    /// half its own (`dashPeriod(ofCurve:)`). Either way the half is a whole
    /// number of its periods, so drawn from its start it begins with a dash
    /// and ends with a complete gap, on the joint and at the centre.
    func forEachSegment(of row: GraphRow, _ body: (GraphSegment, GraphStep, _ dashPeriod: CGFloat) -> Void) {
        let curveOverlap = overlapsJoints ? Self.overlap(for: style.metrics) : 0
        let straightOverlap = overlapsJoints ? Self.straightOverlap(for: style.metrics) : 0
        let straightPeriod = dashPeriod
        let above = row.stepsAbove, below = row.stepsBelow
        func arriving(_ step: GraphStep) -> GraphSegment.Piece {
            let x = style.laneCenter(step.to)
            guard step.from != step.to else {
                let past = Self.isDashed(step) ? 0 : straightOverlap
                return .line(from: CGPoint(x: x, y: jointAbove - past), to: CGPoint(x: x, y: center))
            }
            return piece(GraphCurve.arriving(fromX: style.laneCenter(step.from), toX: x, center: center, height: pitch,
                                             overlap: Self.isDashed(step) ? 0 : curveOverlap))
        }
        func leaving(_ step: GraphStep) -> GraphSegment.Piece {
            let x = style.laneCenter(step.from)
            guard step.from != step.to else {
                let past = Self.isDashed(step) ? 0 : straightOverlap
                return .line(from: CGPoint(x: x, y: center), to: CGPoint(x: x, y: jointBelow + past))
            }
            return piece(GraphCurve.leaving(fromX: x, toX: style.laneCenter(step.to), center: center, height: pitch,
                                            overlap: Self.isDashed(step) ? 0 : curveOverlap))
        }
        /// The step below that `above[index]` is joined with, if any.
        func partner(ofArriving index: Int) -> Int? {
            guard let pair = joinedPair(at: above[index].to, in: row), pair.above == index else { return nil }
            return pair.below
        }
        func isJoined(leaving index: Int) -> Bool {
            joinedPair(at: below[index].from, in: row)?.below == index
        }
        /// Reports `half`, the half `step` draws alone, with its dash period.
        func alone(_ half: GraphSegment.Piece, of step: GraphStep) {
            guard Self.isDashed(step) else { return body(half.alone, step, 0) }
            body(half.alone, step, step.from == step.to ? straightPeriod : dashPeriod(ofCurve: half.length))
        }

        // S halves drawn alone.
        for index in above.indices where above[index].from != above[index].to && partner(ofArriving: index) == nil {
            alone(arriving(above[index]), of: above[index])
        }
        for index in below.indices where below[index].from != below[index].to && !isJoined(leaving: index) {
            alone(leaving(below[index]), of: below[index])
        }
        // Lines joined with an S.
        for index in above.indices {
            guard let next = partner(ofArriving: index), above[index].from != above[index].to
                || below[next].from != below[next].to else { continue }
            body(.joined(arriving(above[index]), leaving(below[next])), above[index], 0)
        }
        // Straight halves drawn alone, and lines joined straight.
        for index in above.indices where above[index].from == above[index].to {
            if let next = partner(ofArriving: index) {
                guard below[next].from == below[next].to else { continue }
                body(.joined(arriving(above[index]), leaving(below[next])), above[index], 0)
            } else {
                alone(arriving(above[index]), of: above[index])
            }
        }
        for index in below.indices where below[index].from == below[index].to && !isJoined(leaving: index) {
            alone(leaving(below[index]), of: below[index])
        }
    }

    /// The arriving and the leaving half that meet at `column` on the row's
    /// centre and are drawn as one path (`forEachSegment`), as indices into
    /// `stepsAbove` and `stepsBelow`; nil if the halves there are drawn
    /// alone.
    ///
    /// Never at the node, which covers where its lines meet. Elsewhere, a
    /// line passing straight through (a straight on each side) is joined,
    /// even where an S also arrives there to fuse with it (§3.3), or leaves
    /// it: that S stays a half of its own. Otherwise the one half that ends
    /// at the column is joined with the one half that starts there: a line
    /// that bends into an S, lands from one, or goes from one S into
    /// another. Only solid halves of the same colour: a dashed half keeps
    /// its own dash pattern, and where two colours meet the line changes
    /// there anyway.
    private func joinedPair(at column: Int, in row: GraphRow) -> (above: Int, below: Int)? {
        guard column != row.node.column else { return nil }
        var arriving: Int?, arrivingCount = 0, straightArriving: Int?
        for index in row.stepsAbove.indices where row.stepsAbove[index].to == column {
            arriving = index
            arrivingCount += 1
            if row.stepsAbove[index].from == column && straightArriving == nil { straightArriving = index }
        }
        var leaving: Int?, leavingCount = 0, straightLeaving: Int?
        for index in row.stepsBelow.indices where row.stepsBelow[index].from == column {
            leaving = index
            leavingCount += 1
            if row.stepsBelow[index].to == column && straightLeaving == nil { straightLeaving = index }
        }
        let pair: (above: Int, below: Int)
        if let straightArriving, let straightLeaving {
            pair = (straightArriving, straightLeaving)
        } else if arrivingCount == 1, leavingCount == 1, let arriving, let leaving {
            pair = (arriving, leaving)
        } else {
            return nil
        }
        let first = row.stepsAbove[pair.above], second = row.stepsBelow[pair.below]
        guard !Self.isDashed(first), !Self.isDashed(second), first.color == second.color else { return nil }
        return pair
    }

    /// Calls `body` with the centre of each circle, `crossingNodeClearance`
    /// in radius, where the crossing band leaves lines alone (§5.2): first
    /// the row's node, where its lines meet, then each point away from it
    /// where an S half meets a straight of its column on its own side of the
    /// centre: an S arriving where a straight also arrives (a join that fuses
    /// with a line already passing, §3.3), or leaving where a straight also
    /// leaves (a line born from one). The straight is drawn after the S
    /// (`forEachSegment`), and its band would cut the S's end off. Where the
    /// straight lies on the other side of the centre (a line that bends or
    /// lands), it doesn't reach the S, and a crossing near there keeps its
    /// gap. A point can come more than once. Allocates nothing.
    func forEachCrossingClearanceCenter(of row: GraphRow, _ body: (CGPoint) -> Void) {
        let node = row.node.column
        body(CGPoint(x: style.laneCenter(node), y: center))
        for step in row.stepsAbove where step.from != step.to && step.to != node
            && row.stepsAbove.contains(where: { $0.from == step.to && $0.to == step.to }) {
            body(CGPoint(x: style.laneCenter(step.to), y: center))
        }
        for step in row.stepsBelow where step.from != step.to && step.from != node
            && row.stepsBelow.contains(where: { $0.from == step.from && $0.to == step.from }) {
            body(CGPoint(x: style.laneCenter(step.from), y: center))
        }
    }

    private func piece(_ bezier: GraphCurve.Bezier) -> GraphSegment.Piece {
        .curve(start: bezier.start, control1: bezier.control1, control2: bezier.control2, end: bezier.end)
    }
}
