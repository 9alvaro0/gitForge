import CoreGraphics
import Foundation
import Testing
@testable import gitForge

@Suite("Graph — row geometry")
struct GraphRowGeometryTests {

    private static func step(_ from: Int, _ to: Int, _ stroke: GraphStroke = .solid) -> GraphStep {
        GraphStep(from: from, to: to, color: .pool(0), stroke: stroke)
    }

    private static func row(above: [GraphStep] = [], below: [GraphStep] = []) -> GraphRow {
        GraphRow(node: GraphNode(column: 0, kind: .commit, color: .head, isGhost: false),
                 stepsAbove: above, stepsBelow: below, width: 3)
    }

    /// The geometry of a row of `density`, in a canvas sized as the table sizes
    /// it. Regular: lane `n` is centred at `14 + 14 n`; a 28 pt row plus the
    /// 1 pt gap is a 29 pt pitch, and with the 3 pt bleed past each joint the
    /// canvas is 35 pt tall, its centre at 17.5 and its joints at 3 and 32.
    private static func geometry(_ density: DensityMetrics = .regular, overlapsJoints: Bool = true) -> GraphRowGeometry {
        let pitch = density.rowList + HistoryTableLayout.rowSpacing
        let height = GraphRowGeometry.canvasHeight(pitch: pitch, metrics: density.graph)
        return GraphRowGeometry(style: GraphStyle(metrics: density.graph), size: CGSize(width: 120, height: height),
                                overlapsJoints: overlapsJoints)
    }

    private static func segments(_ row: GraphRow, in geometry: GraphRowGeometry = geometry()) -> [(GraphSegment, GraphStep)] {
        var all: [(GraphSegment, GraphStep)] = []
        geometry.forEachSegment(of: row) { segment, step, _ in all.append((segment, step)) }
        return all
    }

    /// Every half of `row` with the dash phase it starts with.
    private static func phasedSegments(_ row: GraphRow, in geometry: GraphRowGeometry = geometry())
        -> [(segment: GraphSegment, step: GraphStep, dashPhase: CGFloat)] {
        var all: [(segment: GraphSegment, step: GraphStep, dashPhase: CGFloat)] = []
        geometry.forEachSegment(of: row) { segment, step, dashPhase in all.append((segment, step, dashPhase)) }
        return all
    }

    /// Whether `a` and `b` are the same point of a dash pattern of `period`
    /// (they may differ by whole periods), within 0.01.
    private static func expectSamePhase(_ a: CGFloat, _ b: CGFloat, period: CGFloat, _ message: String = "",
                                        sourceLocation: SourceLocation = #_sourceLocation) {
        var difference = (a - b).truncatingRemainder(dividingBy: period)
        if difference < 0 { difference += period }
        #expect(min(difference, period - difference) < 0.01, "\(a) vs \(b) mod \(period) \(message)",
                sourceLocation: sourceLocation)
    }

    private static func curve(_ bezier: GraphCurve.Bezier) -> GraphSegment {
        .curve(start: bezier.start, control1: bezier.control1, control2: bezier.control2, end: bezier.end)
    }

    @Test("The canvas reaches past each joint far enough for the overlap and the stroke around it",
          arguments: [DensityMetrics.regular, .compact])
    func bleed(density: DensityMetrics) {
        let metrics = density.graph
        let overlap = GraphRowGeometry.overlap(for: metrics)
        let bleed = GraphRowGeometry.bleed(for: metrics)
        #expect(overlap >= metrics.edgeWidth / 2)
        #expect(bleed >= overlap + metrics.edgeWidth / 2 + GraphRowGeometry.antialiasMargin)
        #expect(bleed == bleed.rounded())
        // The node stays on the row's centre, the joints in the middle of the gaps.
        let geometry = Self.geometry(density)
        #expect(geometry.bleed == bleed)
        #expect(geometry.pitch == density.rowList + HistoryTableLayout.rowSpacing)
        #expect(geometry.center - geometry.jointAbove == geometry.pitch / 2)
        #expect(geometry.jointBelow - geometry.center == geometry.pitch / 2)
    }

    @Test("A straight step above runs from the joint above to the centre; below, from the centre to the joint below")
    func straightHalves() {
        let segments = Self.segments(Self.row(above: [Self.step(0, 0)], below: [Self.step(0, 0), Self.step(1, 1)]))
        #expect(segments.map(\.0) == [
            .line(from: CGPoint(x: 14, y: 3), to: CGPoint(x: 14, y: 17.5)),
            .line(from: CGPoint(x: 14, y: 17.5), to: CGPoint(x: 14, y: 32)),
            .line(from: CGPoint(x: 28, y: 17.5), to: CGPoint(x: 28, y: 32)),
        ])
        // A dimmed row draws the same straight halves.
        let dimmed = Self.segments(Self.row(above: [Self.step(0, 0)], below: [Self.step(0, 0), Self.step(1, 1)]),
                                   in: Self.geometry(overlapsJoints: false))
        #expect(dimmed.map(\.0) == segments.map(\.0))
    }

    @Test("A step above draws the arriving half of its S; a step below the leaving half, over the full pitch and past the joints")
    func curveHalves() {
        let segments = Self.segments(Self.row(above: [Self.step(1, 0)], below: [Self.step(0, 2)]))
        #expect(segments.map(\.0) == [
            Self.curve(GraphCurve.arriving(fromX: 28, toX: 14, center: 17.5, height: 29, overlap: 1)),
            Self.curve(GraphCurve.leaving(fromX: 14, toX: 42, center: 17.5, height: 29, overlap: 1)),
        ])
        let dimmed = Self.segments(Self.row(above: [Self.step(1, 0)], below: [Self.step(0, 2)]),
                                   in: Self.geometry(overlapsJoints: false))
        #expect(dimmed.map(\.0) == [
            Self.curve(GraphCurve.arriving(fromX: 28, toX: 14, center: 17.5, height: 29)),
            Self.curve(GraphCurve.leaving(fromX: 14, toX: 42, center: 17.5, height: 29)),
        ])
    }

    @Test("Curves come first, then the straight halves, each with its own step")
    func drawingOrder() {
        let above = [Self.step(0, 0), Self.step(2, 1, .stash)]
        let below = [Self.step(0, 0), Self.step(1, 2)]
        let steps = Self.segments(Self.row(above: above, below: below)).map(\.1)
        #expect(steps == [above[1], below[1], above[0], below[0]])
    }

    @Test("Every half stays inside the canvas with its whole stroke", arguments: [DensityMetrics.regular, .compact])
    func strokeInsideTheCanvas(density: DensityMetrics) {
        let halfStroke = density.graph.edgeWidth / 2
        let row = Self.row(above: [Self.step(0, 0), Self.step(2, 0), Self.step(0, 3), Self.step(5, 1),
                                   Self.step(4, 3, .stash)],
                           below: [Self.step(0, 0), Self.step(0, 1), Self.step(3, 2), Self.step(1, 6),
                                   Self.step(2, 5, .stash)])
        for overlapsJoints in [true, false] {
            let geometry = Self.geometry(density, overlapsJoints: overlapsJoints)
            for (segment, _) in Self.segments(row, in: geometry) {
                for point in segment.samples {
                    #expect(point.y - halfStroke >= 0 && point.y + halfStroke <= geometry.size.height, "\(segment)")
                }
            }
        }
    }

    @Test("Adjacent rows draw their halves of an S past the joint along the same S, by half the stroke at least",
          arguments: [DensityMetrics.regular, .compact])
    func curveHalvesOverlap(density: DensityMetrics) {
        for (from, to) in [(0, 2), (3, 1), (0, 1), (6, 0)] {
            let step = Self.step(from, to)
            let upper = Self.segments(Self.row(below: [step]), in: Self.geometry(density))[0].0
            let lower = Self.segments(Self.row(above: [step]), in: Self.geometry(density))[0].0
            Self.expectJoin(upper, lower, of: step, in: Self.geometry(density))
        }
    }

    @Test("A stash's dashed halves meet exactly on the joint, neither running past it")
    func stashHalves() {
        let geometry = Self.geometry()
        for step in [Self.step(1, 0, .stash), Self.step(0, 3, .stash)] {
            let upper = Self.segments(Self.row(below: [step]))[0].0
            let lower = Self.segments(Self.row(above: [step]))[0].0
            #expect(lower.samples.first!.y == geometry.jointAbove)
            #expect(upper.samples.last!.y == geometry.jointBelow)
            Self.expectJoin(upper, lower, of: step, in: geometry)
        }
    }

    @Test("A dimmed row's halves meet in the middle of the gap with the same point and the same tangent")
    func halvesMeet() {
        // Rows one pitch apart: the lower canvas starts one pitch below the upper one.
        let geometry = Self.geometry(overlapsJoints: false)
        for (from, to) in [(0, 2), (3, 1)] {
            let step = Self.step(from, to)
            let upper = Self.segments(Self.row(below: [step]), in: geometry)[0].0
            let lower = Self.segments(Self.row(above: [step]), in: geometry)[0].0
            guard case let .curve(_, _, upperControl, upperEnd) = upper,
                  case let .curve(lowerStart, lowerControl, _, _) = lower else {
                Issue.record("\(from)>\(to) should draw two curve halves")
                continue
            }
            #expect(upperEnd == CGPoint(x: lowerStart.x, y: lowerStart.y + geometry.pitch))
            #expect(upperEnd.y == geometry.jointBelow)
            // The same tangent on both sides: one S split in two, no kink.
            #expect(upperEnd.x - upperControl.x == lowerControl.x - lowerStart.x)
            #expect(upperEnd.y - upperControl.y == lowerControl.y - lowerStart.y)
            Self.expectJoin(upper, lower, of: step, in: geometry)
        }
        // A straight step: two verticals at the same x, meeting on the joint.
        let upper = Self.segments(Self.row(below: [Self.step(1, 1)]), in: geometry)[0].0.points
        let lower = Self.segments(Self.row(above: [Self.step(1, 1)]), in: geometry)[0].0.points
        #expect(upper.last == CGPoint(x: lower[0].x, y: lower[0].y + geometry.pitch))
    }

    @Test("Half a pitch holds a whole number of dash periods", arguments: [(29.0, 7.25), (23.0, 5.75)])
    func dashPeriod(pitch: CGFloat, period: CGFloat) {
        #expect(GraphRowGeometry.dashPeriod(pitch: pitch) == period)
    }

    @Test("The period stays near a 3–3 dash and half a pitch always holds a whole number of them",
          arguments: Array(24...80))
    func dashPeriodHoldsWholePeriods(pitch: Int) {
        let pitch = CGFloat(pitch)
        let period = GraphRowGeometry.dashPeriod(pitch: pitch)
        #expect(period >= 4.5 && period <= 7.5, "\(period)")
        let count = pitch / 2 / period
        #expect(abs(count - count.rounded()) < 1e-9, "\(count)")
    }

    @Test("A geometry's dash period is the one of its own pitch", arguments: [DensityMetrics.regular, .compact])
    func geometryDashPeriod(density: DensityMetrics) {
        let geometry = Self.geometry(density)
        #expect(geometry.dashPeriod == GraphRowGeometry.dashPeriod(pitch: geometry.pitch))
        #expect(geometry.dashPeriod == (density == .regular ? 7.25 : 5.75))
    }

    @Test("Stash and ghost steps are dashed; solid ones are not")
    func isDashed() {
        #expect(GraphRowGeometry.isDashed(Self.step(0, 1, .stash)))
        #expect(GraphRowGeometry.isDashed(Self.step(0, 0, .stash)))
        #expect(GraphRowGeometry.isDashed(Self.step(0, 1, .ghost)))
        #expect(GraphRowGeometry.isDashed(Self.step(2, 2, .ghost)))
        #expect(!GraphRowGeometry.isDashed(Self.step(0, 1)))
        #expect(!GraphRowGeometry.isDashed(Self.step(2, 2)))
    }

    @Test("A half starts its dash at 0, unless it is a curve arriving: that one carries on from the half that left",
          arguments: [DensityMetrics.regular, .compact], [GraphStroke.solid, .ghost, .stash])
    func dashPhases(density: DensityMetrics, stroke: GraphStroke) {
        let geometry = Self.geometry(density)
        let period = geometry.dashPeriod
        let row = Self.row(above: [Self.step(1, 0, stroke), Self.step(2, 3, stroke), Self.step(4, 4, stroke)],
                           below: [Self.step(0, 2, stroke), Self.step(3, 1, stroke), Self.step(5, 5, stroke)])
        for (segment, step, phase) in Self.phasedSegments(row, in: geometry) {
            let arrivesBent = step.from != step.to && row.stepsAbove.contains(step)
            if GraphRowGeometry.isDashed(step) && arrivesBent {
                // The mirror of this half left the row above with its dash from 0: this one picks up there.
                #expect(phase >= 0 && phase < period, "\(step) \(phase)")
                Self.expectSamePhase(phase, segment.length, period: period, "\(step)")
            } else {
                #expect(phase == 0, "\(step) \(phase)")
            }
        }
    }

    @Test("The dash continues across the joint for straights and S curves up to six columns",
          arguments: [DensityMetrics.regular, .compact], [0, 1, 2, 3, 6])
    func dashAcrossJoint(density: DensityMetrics, width: Int) {
        // The upper row leaves column 0 for column `width` dashed; the lower row arrives with it.
        let geometry = Self.geometry(density)
        let step = GraphStep(from: 0, to: width, color: .pool(0), stroke: .ghost)
        let upper = Self.phasedSegments(Self.row(below: [step]), in: geometry)[0]
        let lower = Self.phasedSegments(Self.row(above: [step]), in: geometry)[0]
        #expect(upper.dashPhase == 0)
        Self.expectSamePhase(upper.dashPhase + upper.segment.length, lower.dashPhase, period: geometry.dashPeriod,
                             "width \(width)")
    }

    @Test("The dash continues across the joint whichever way the S leans and for every dashed stroke",
          arguments: [DensityMetrics.regular, .compact], [GraphStroke.ghost, .stash])
    func dashAcrossJointBothWays(density: DensityMetrics, stroke: GraphStroke) {
        let geometry = Self.geometry(density)
        for (from, to) in [(0, 1), (1, 0), (4, 1), (5, 0), (1, 6), (6, 0), (3, 3)] {
            let step = Self.step(from, to, stroke)
            let upper = Self.phasedSegments(Self.row(below: [step]), in: geometry)[0]
            let lower = Self.phasedSegments(Self.row(above: [step]), in: geometry)[0]
            Self.expectSamePhase(upper.dashPhase + upper.segment.length, lower.dashPhase, period: geometry.dashPeriod,
                                 "\(step)")
        }
    }

    @Test("In the gitflow graph, drawn dashed, the dash continues across every joint",
          arguments: [DensityMetrics.regular, .compact])
    func gitflowDashAcrossJoints(density: DensityMetrics) {
        let refs = GraphFixture.gitflowRefs(head: "feature/cart")
        let rows = CommitGraphEngine.layout(GraphInput(commits: GraphFixture.gitflow, headSha: "cartPayment",
                                                       refs: refs, paletteSize: 4)).rows
        func dashed(_ steps: [GraphStep]) -> [GraphStep] {
            steps.map { GraphStep(from: $0.from, to: $0.to, color: $0.color, stroke: .ghost) }
        }
        let geometry = Self.geometry(density)
        var bent = 0
        for boundary in 0..<(rows.count - 1) {
            let leaving = Self.phasedSegments(Self.row(below: dashed(rows[boundary].stepsBelow)), in: geometry)
            let arriving = Self.phasedSegments(Self.row(above: dashed(rows[boundary + 1].stepsAbove)), in: geometry)
            for upper in leaving {
                guard let lower = arriving.first(where: { $0.step == upper.step }) else { continue }
                bent += upper.step.from == upper.step.to ? 0 : 1
                Self.expectSamePhase(upper.dashPhase + upper.segment.length, lower.dashPhase,
                                     period: geometry.dashPeriod, "boundary \(boundary) \(upper.step)")
            }
        }
        #expect(bent > 0, "the graph should have bent steps to test")
    }

    @Test("Dashed halves end exactly on the joint; solid ones still overlap it",
          arguments: [DensityMetrics.regular, .compact], [true, false])
    func dashedNoOverlap(density: DensityMetrics, overlapsJoints: Bool) {
        let geometry = Self.geometry(density, overlapsJoints: overlapsJoints)
        let solidOverlap = overlapsJoints ? GraphRowGeometry.overlap(for: density.graph) : 0
        for (from, to) in [(0, 2), (3, 1), (0, 1), (6, 0)] {
            for stroke in [GraphStroke.stash, .ghost, .solid] {
                let step = Self.step(from, to, stroke)
                let upper = Self.segments(Self.row(below: [step]), in: geometry)[0].0
                let lower = Self.segments(Self.row(above: [step]), in: geometry)[0].0
                let past = GraphRowGeometry.isDashed(step) ? 0 : solidOverlap
                #expect(abs(upper.samples.last!.y - (geometry.jointBelow + past)) < 1e-9, "\(step) leaving")
                #expect(abs(lower.samples.first!.y - (geometry.jointAbove - past)) < 1e-9, "\(step) arriving")
            }
        }
    }

    @Test("In the gitflow graph every half a row leaves joins the half the next row arrives with",
          arguments: [DensityMetrics.regular, .compact], [true, false])
    func gitflowJoins(density: DensityMetrics, overlapsJoints: Bool) {
        let refs = GraphFixture.gitflowRefs(head: "feature/cart")
        let rows = CommitGraphEngine.layout(GraphInput(commits: GraphFixture.gitflow, headSha: "cartPayment",
                                                       refs: refs, paletteSize: 4)).rows
        let geometry = Self.geometry(density, overlapsJoints: overlapsJoints)
        for boundary in 0..<(rows.count - 1) {
            let leaving = Self.segments(Self.row(below: rows[boundary].stepsBelow), in: geometry)
            let arriving = Self.segments(Self.row(above: rows[boundary + 1].stepsAbove), in: geometry)
            #expect(leaving.count == arriving.count, "boundary \(boundary)")
            #expect(Set(leaving.map(\.1)) == Set(arriving.map(\.1)), "boundary \(boundary)")
            #expect(Set(leaving.map(\.1)).count == leaving.count, "boundary \(boundary)")
            for (upper, step) in leaving {
                guard let lower = arriving.first(where: { $0.1 == step })?.0 else { continue }
                Self.expectJoin(upper, lower, of: step, in: geometry)
            }
        }
    }

    /// Checks that `upper`, the half one row leaves `step` with, and `lower`,
    /// the half the next row arrives with (in its own canvas, one pitch
    /// down), draw one step across the joint between the rows.
    ///
    /// A straight step: two verticals meeting on the joint. A curve: both
    /// halves on the step's one S, from the upper row's centre and to the
    /// lower row's, each running past the joint by the overlap (none for a
    /// dimmed row, and none for a dashed step, which would draw the overlap
    /// twice over). Running past by half the stroke or more also puts
    /// everything a half leaves to the other row, stroke included, on the
    /// other row's side of the joint.
    private static func expectJoin(_ upper: GraphSegment, _ lower: GraphSegment, of step: GraphStep,
                                   in geometry: GraphRowGeometry,
                                   sourceLocation: SourceLocation = #_sourceLocation) {
        let style = geometry.style
        let pitch = geometry.pitch, center = geometry.center
        let lower = lower.offset(by: pitch)
        guard step.from != step.to else {
            let x = style.laneCenter(step.from)
            #expect(upper == .line(from: CGPoint(x: x, y: center), to: CGPoint(x: x, y: geometry.jointBelow)),
                    sourceLocation: sourceLocation)
            #expect(lower == .line(from: CGPoint(x: x, y: geometry.jointBelow), to: CGPoint(x: x, y: center + pitch)),
                    sourceLocation: sourceLocation)
            return
        }
        let s = SCurve(x0: style.laneCenter(step.from), x1: style.laneCenter(step.to), top: center, pitch: pitch)
        for point in upper.samples + lower.samples {
            #expect(s.contains(point), "\(step) \(point)", sourceLocation: sourceLocation)
        }
        #expect(upper.samples.first == CGPoint(x: s.x0, y: center), sourceLocation: sourceLocation)
        #expect(lower.samples.last == CGPoint(x: s.x1, y: center + pitch), sourceLocation: sourceLocation)
        let joint = s.point(at: 0.5)
        #expect(joint.y == geometry.jointBelow, sourceLocation: sourceLocation)

        let halfStroke = style.metrics.edgeWidth / 2
        let past = geometry.overlapsJoints && !GraphRowGeometry.isDashed(step)
            ? GraphRowGeometry.overlap(for: style.metrics) : 0
        let leavingPast = past, arrivingPast = past
        let upperEnd = upper.samples.last!, lowerStart = lower.samples.first!
        #expect(abs(upperEnd.y - joint.y - leavingPast) < 1e-9, "\(step)", sourceLocation: sourceLocation)
        #expect(abs(joint.y - lowerStart.y - arrivingPast) < 1e-9, "\(step)", sourceLocation: sourceLocation)
        if geometry.overlapsJoints && !GraphRowGeometry.isDashed(step) {
            // Past the joint by half the stroke, downwards and along the S.
            #expect(upperEnd.y - joint.y >= halfStroke, "\(step)", sourceLocation: sourceLocation)
            #expect(hypot(upperEnd.x - joint.x, upperEnd.y - joint.y) >= halfStroke, sourceLocation: sourceLocation)
            #expect(joint.y - lowerStart.y >= halfStroke, "\(step)", sourceLocation: sourceLocation)
            #expect(hypot(lowerStart.x - joint.x, lowerStart.y - joint.y) >= halfStroke,
                    sourceLocation: sourceLocation)
        }
    }
}

private extension GraphSegment {
    /// Start first, end last.
    var points: [CGPoint] {
        switch self {
        case let .line(from, to): [from, to]
        case let .curve(start, control1, control2, end): [start, control1, control2, end]
        }
    }

    /// The length of the half: a line's distance, a curve's arc length.
    var length: CGFloat {
        switch self {
        case let .line(from, to): hypot(to.x - from.x, to.y - from.y)
        case let .curve(start, control1, control2, end):
            GraphCurve.arcLength((start: start, control1: control1, control2: control2, end: end))
        }
    }

    /// Points along the half as drawn, its start first and its end last.
    var samples: [CGPoint] {
        (0...32).map { index -> CGPoint in
            let t = CGFloat(index) / 32, u = 1 - t
            switch self {
            case let .line(from, to):
                return CGPoint(x: u * from.x + t * to.x, y: u * from.y + t * to.y)
            case let .curve(p0, p1, p2, p3):
                let (b0, b1, b2, b3) = (u * u * u, 3 * u * u * t, 3 * u * t * t, t * t * t)
                return CGPoint(x: b0 * p0.x + b1 * p1.x + b2 * p2.x + b3 * p3.x,
                               y: b0 * p0.y + b1 * p1.y + b2 * p2.y + b3 * p3.y)
            }
        }
    }

    /// The same half moved `dy` down.
    func offset(by dy: CGFloat) -> GraphSegment {
        func move(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x, y: p.y + dy) }
        return switch self {
        case let .line(from, to): .line(from: move(from), to: move(to))
        case let .curve(p0, p1, p2, p3): .curve(start: move(p0), control1: move(p1), control2: move(p2), end: move(p3))
        }
    }
}

/// The whole S of a step, written out from §5.1 rather than taken from
/// `GraphCurve`: from `(x0, top)` to `(x1, top + pitch)`, controls
/// `(x0, top + pitch/2)` and `(x1, top + pitch/2)`.
private struct SCurve {
    let x0: CGFloat
    let x1: CGFloat
    let top: CGFloat
    let pitch: CGFloat

    func point(at t: CGFloat) -> CGPoint {
        let u = 1 - t
        let (b0, b1, b2, b3) = (u * u * u, 3 * u * u * t, 3 * u * t * t, t * t * t)
        return CGPoint(x: (b0 + b1) * x0 + (b2 + b3) * x1, y: top + (b1 + b2) * pitch / 2 + b3 * pitch)
    }

    /// Whether `point` lies on the S. Its y rises with `t`, so the `t` at the
    /// point's height is found by bisection; the S's x there must match.
    func contains(_ point: CGPoint) -> Bool {
        var low: CGFloat = 0, high: CGFloat = 1
        for _ in 0..<64 {
            let mid = (low + high) / 2
            if self.point(at: mid).y < point.y { low = mid } else { high = mid }
        }
        let onS = self.point(at: (low + high) / 2)
        return abs(onS.x - point.x) < 1e-6 && abs(onS.y - point.y) < 1e-6
    }
}
