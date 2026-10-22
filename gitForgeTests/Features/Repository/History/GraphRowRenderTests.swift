import CoreGraphics
import SwiftUI
import Testing
@testable import gitForge

/// Renders graph rows the way the History table stacks them, over a pure red
/// background no line is drawn in, and reads their pixels back: where the
/// crossing gap (§5.2) clears a line, the row's own background shows. The
/// ghost tests (§4.3) draw over black instead, so a translucent line reads as
/// its colour scaled by its opacity.
///
/// Points are in the rendered view's coordinates, from its top-left corner:
/// the row (or the first of the stacked rows) runs from `y = 0` to its height,
/// so a row's canvas, which overhangs it by `bleed`, has its centre at half
/// the row height. Rows touch (no gap between them), so the joint between two
/// stacked rows is their shared edge.
@Suite("Graph — rendered rows")
@MainActor
struct GraphRowRenderTests {

    /// Columns every test row is drawn with.
    private static let lanes = 4

    /// What shows where nothing is drawn.
    private static let background = Pixel(red: 255, green: 0, blue: 0, alpha: 255)

    /// Fixed colours, none of them near red, whatever the system accent is: HEAD's
    /// line is pure blue.
    private static func style(_ metrics: GraphMetrics, ghostOpacity: Double = 0.6) -> GraphStyle {
        GraphStyle(metrics: metrics, accent: .violet, accentColor: Color(red: 0, green: 0, blue: 1), dark: true,
                   nodeFill: .black, ghostOpacity: ghostOpacity)
    }

    private static func step(_ from: Int, _ to: Int, _ color: GraphColorRole,
                             stroke: GraphStroke = .solid) -> GraphStep {
        GraphStep(from: from, to: to, color: color, stroke: stroke)
    }

    private static func row(node column: Int, above: [GraphStep] = [], below: [GraphStep] = [],
                            color: GraphColorRole = .pool(2), isGhost: Bool = false, lanes: Int = lanes) -> GraphRow {
        GraphRow(node: GraphNode(column: column, kind: .commit, color: color, isGhost: isGhost),
                 stepsAbove: above, stepsBelow: below, width: lanes)
    }

    /// `rows` stacked `rowSpacing` apart (no gap by default), each `rowHeight`
    /// tall, over `background`.
    private static func render(_ rows: [GraphRow], metrics: GraphMetrics, rowHeight: CGFloat, rowSpacing: CGFloat = 0,
                               lanes: Int = lanes, ghostOpacity: Double = 0.6,
                               background: Color = Color(red: 1, green: 0, blue: 0),
                               sourceLocation: SourceLocation = #_sourceLocation) -> Rendering? {
        let style = style(metrics, ghostOpacity: ghostOpacity)
        let size = CGSize(width: style.gutterWidth(lanes: lanes),
                          height: rowHeight * CGFloat(rows.count) + rowSpacing * CGFloat(max(rows.count - 1, 0)))
        return render(ZStack(alignment: .topLeading) {
            background
            VStack(spacing: rowSpacing) {
                ForEach(rows.indices, id: \.self) { index in
                    GraphColumnView(row: rows[index], maxLanes: lanes, style: style, rowSpacing: rowSpacing)
                        .frame(height: rowHeight)
                }
            }
        }, size: size, sourceLocation: sourceLocation)
    }

    /// `view`, framed to `size` and rendered at `scale` pixels per point (twice
    /// the point size by default); nil, with an issue recorded, if the
    /// renderer gives no image of that size.
    private static func render(_ view: some View, size: CGSize, scale: CGFloat = 2,
                               sourceLocation: SourceLocation = #_sourceLocation) -> Rendering? {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
        renderer.scale = scale
        guard let image = renderer.cgImage, let rendering = Rendering(image, scale: scale),
              rendering.width == Int(size.width * scale), rendering.height == Int(size.height * scale) else {
            Issue.record("No \(size) image rendered at \(scale)x", sourceLocation: sourceLocation)
            return nil
        }
        return rendering
    }

    // MARK: - The gap

    /// The node in column 0; a line arrives from column 3 into it, across the
    /// line passing straight down column 1.
    private static let crossing = row(node: 0, above: [step(3, 0, .pool(1)), step(1, 1, .pool(0))],
                                      below: [step(1, 1, .pool(0))])

    /// The middle of the band the straight line in column 1 clears on its
    /// right, on the arriving curve of `crossing`, and a point further along
    /// the curve, away from the band.
    private static func crossingPoints(_ metrics: GraphMetrics, rowHeight: CGFloat) -> (near: CGPoint, far: CGPoint) {
        let style = style(metrics)
        let arriving = GraphCurve.arriving(fromX: style.laneCenter(3), toX: style.laneCenter(0), center: rowHeight / 2,
                                           height: rowHeight)
        let bandMiddle = style.laneCenter(1) + metrics.edgeWidth / 2 + metrics.crossingGap / 2
        return (point(on: arriving, atX: bandMiddle), point(on: arriving, atX: style.laneCenter(1) + 6))
    }

    @Test("Where a straight line crosses a curve, the curve shows the row's background beside it",
          arguments: [DensityMetrics.regular, .compact])
    func gapAtCrossing(density: DensityMetrics) {
        let metrics = density.graph, rowHeight = density.rowList
        let (near, far) = Self.crossingPoints(metrics, rowHeight: rowHeight)
        // Out of reach of the clearance around the node and where curves meet the centre.
        for point in Self.protectedPoints(of: Self.crossing, style: Self.style(metrics), rowHeight: rowHeight) {
            #expect(near.distance(to: point) > metrics.crossingNodeClearance, "\(near) vs \(point)")
        }
        guard let image = Self.render([Self.crossing], metrics: metrics, rowHeight: rowHeight) else { return }
        // The background, whole: the band erased the curve and nothing under the row.
        #expect(image.pixel(at: near).isClose(to: Self.background), "\(near): \(image.pixel(at: near))")
        #expect(!image.pixel(at: far).isClose(to: Self.background), "\(far): \(image.pixel(at: far))")
    }

    @Test("The band erases only the row's own lines, never what lies under them",
          arguments: [DensityMetrics.regular, .compact])
    func gapKeepsTheBackground(density: DensityMetrics) {
        let metrics = density.graph, rowHeight = density.rowList
        let style = Self.style(metrics)
        let row = Self.crossing
        // Here the background is painted into the row's own canvas, under its lines, as it would be if the
        // canvas were drawn straight onto the row's background (its selection or hover): the gap must still
        // show it. The canvas has no overhang here, so a row's point lies `bleed` lower in it.
        let size = CGSize(width: style.gutterWidth(lanes: Self.lanes),
                          height: GraphRowGeometry.canvasHeight(pitch: rowHeight, metrics: metrics))
        let canvas = Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red: 1, green: 0, blue: 0)))
            GraphRowPainter(style: style, size: size).drawSteps(of: row, in: &context)
        }
        let (near, far) = Self.crossingPoints(metrics, rowHeight: rowHeight)
        let bleed = GraphRowGeometry.bleed(for: metrics)
        guard let image = Self.render(canvas, size: size) else { return }
        let gap = image.pixel(at: CGPoint(x: near.x, y: near.y + bleed))
        #expect(gap.isClose(to: Self.background), "\(near): \(gap)")
        let line = image.pixel(at: CGPoint(x: far.x, y: far.y + bleed))
        #expect(!line.isClose(to: Self.background), "\(far): \(line)")
    }

    @Test("Without a crossing gap the curve is drawn through the band", arguments: [DensityMetrics.regular, .compact])
    func noGap(density: DensityMetrics) {
        let metrics = density.graph, rowHeight = density.rowList
        let (near, _) = Self.crossingPoints(metrics, rowHeight: rowHeight)
        guard let image = Self.render([Self.crossing], metrics: metrics.withCrossingGap(0), rowHeight: rowHeight)
        else { return }
        #expect(!image.pixel(at: near).isClose(to: Self.background), "\(near): \(image.pixel(at: near))")
    }

    @Test("A row with no S draws its straight lines, solid and ghost, just as a row with one does",
          arguments: [DensityMetrics.regular, .compact])
    func rowWithoutCurvesDrawsTheSame(density: DensityMetrics) {
        let metrics = density.graph, rowHeight = density.rowList
        let style = Self.style(metrics)
        // The node's line in column 0, a solid line through column 2 and a ghost one through column 3.
        let steps = [Self.step(0, 0, .head), Self.step(2, 2, .pool(0)), Self.step(3, 3, .pool(1), stroke: .ghost)]
        let straight = Self.row(node: 0, above: steps, below: steps)
        // The same with an S arriving into the node from column 1, well away from columns 2 and 3.
        let bent = Self.row(node: 0, above: steps + [Self.step(1, 0, .pool(3))], below: steps)
        guard let plain = Self.render([straight], metrics: metrics, rowHeight: rowHeight),
              let layered = Self.render([bent], metrics: metrics, rowHeight: rowHeight) else { return }
        let strip = CGRect(x: style.laneCenter(2) - 4, y: 0, width: style.laneCenter(3) - style.laneCenter(2) + 8,
                           height: rowHeight)
        var lit = 0
        for center in plain.pixelCenters(in: strip) {
            let pixel = plain.pixel(at: center)
            lit += pixel.isClose(to: Self.background) ? 0 : 1
            #expect(pixel.isClose(to: layered.pixel(at: center), tolerance: 1),
                    "\(center): \(pixel) without an S, \(layered.pixel(at: center)) with one")
        }
        #expect(lit > 0, "nothing drawn in the strip")
    }

    @Test("Lines meeting at the commit are not cut within the clearance", arguments: [DensityMetrics.regular, .compact])
    func nodeClearance(density: DensityMetrics) {
        let metrics = density.graph, rowHeight = density.rowList
        let style = Self.style(metrics)
        let row = Self.row(node: 1, above: [Self.step(0, 1, .pool(1)), Self.step(1, 1, .pool(0))],
                           below: [Self.step(1, 1, .pool(0))])
        let arriving = GraphCurve.arriving(fromX: style.laneCenter(0), toX: style.laneCenter(1),
                                           center: rowHeight / 2, height: rowHeight)
        // In the middle of the band the straight line clears on its left, near the node.
        let point = Self.point(on: arriving, atX: style.laneCenter(1) - metrics.edgeWidth / 2 - metrics.crossingGap / 2)
        let node = CGPoint(x: style.laneCenter(1), y: rowHeight / 2)
        #expect(point.distance(to: node) < metrics.crossingNodeClearance)
        guard let image = Self.render([row], metrics: metrics, rowHeight: rowHeight) else { return }
        #expect(!image.pixel(at: point).isClose(to: Self.background), "\(point): \(image.pixel(at: point))")
    }

    @Test("A line that meets another at its commit is drawn whole beside it",
          arguments: [DensityMetrics.regular, .compact])
    func meetingAtCommitDrawnWhole(density: DensityMetrics) {
        let row = Self.row(node: 1, above: [Self.step(0, 1, .pool(1)), Self.step(1, 1, .pool(0))],
                           below: [Self.step(1, 1, .pool(0))])
        expectDrawnWhole(row.stepsAbove[0], arrivingIn: row, besideStraightIn: 1, density: density)
    }

    @Test("A join that fuses with a line already passing is drawn whole beside it, away from the commit",
          arguments: [DensityMetrics.regular, .compact])
    func fusedJoinDrawnWhole(density: DensityMetrics) {
        // §3.3: the merge's connector from column 0 joins the line passing down column 1 at the centre.
        let row = Self.row(node: 0, above: [Self.step(0, 0, .head), Self.step(0, 1, .pool(1)), Self.step(1, 1, .pool(0))],
                           below: [Self.step(0, 0, .head), Self.step(1, 1, .pool(0))])
        expectDrawnWhole(row.stepsAbove[1], arrivingIn: row, besideStraightIn: 1, density: density)
    }

    @Test("Where an S crosses a straight line right on the joint between rows, neither row leaves a sliver of it in the gap",
          arguments: [DensityMetrics.regular, .compact])
    func gapOnJoint(density: DensityMetrics) {
        let metrics = density.graph, rowHeight = density.rowList
        let style = Self.style(metrics)
        // An S from column 0 to column 2 crosses column 1 in the middle, on the joint.
        let bend = Self.step(0, 2, .pool(1)), line = Self.step(1, 1, .pool(0))
        let upper = Self.row(node: 0, below: [bend, line])
        let lower = Self.row(node: 2, above: [bend, line])
        guard let image = Self.render([upper, lower], metrics: metrics, rowHeight: rowHeight) else { return }
        let s = GraphCurve.step(fromX: style.laneCenter(0), toX: style.laneCenter(2), top: rowHeight / 2,
                                height: rowHeight)
        let polyline = Self.polyline(s)
        let nodes = [CGPoint(x: style.laneCenter(0), y: rowHeight / 2),
                     CGPoint(x: style.laneCenter(2), y: rowHeight * 3 / 2)]
        let halfStroke = metrics.edgeWidth / 2
        var above = 0, below = 0
        for center in image.pixelCenters(in: Self.bounds(of: s, outset: metrics.edgeWidth)) {
            // On the S's stroke, in the band beside the straight line's stroke, clear of both edges.
            let offset = abs(center.x - style.laneCenter(1))
            guard Self.distance(from: center, to: polyline) <= halfStroke - 0.5,
                  offset >= halfStroke + 0.5, offset <= halfStroke + metrics.crossingGap - 0.5 else { continue }
            for node in nodes {
                #expect(center.distance(to: node) > metrics.crossingNodeClearance, "\(center)")
            }
            if center.y < rowHeight { above += 1 } else { below += 1 }
            #expect(image.pixel(at: center).isClose(to: Self.background), "\(center): \(image.pixel(at: center))")
        }
        #expect(above > 0 && below > 0, "\(above) above the joint, \(below) below")
    }

    @Test("Where an S crosses another close to the point where a line bends into it, the lower S shows the background beside the upper one",
          arguments: [DensityMetrics.regular, .compact])
    func gapNearABend(density: DensityMetrics) {
        let metrics = density.graph, rowHeight = density.rowList
        let style = Self.style(metrics)
        // A line arrives straight down column 2 and bends there into an S to column 3; an S from column 3 to
        // column 0 leaves the row under it and crosses it a few points from the bend.
        let bend = Self.step(2, 3, .pool(0)), under = Self.step(3, 0, .pool(1))
        let row = Self.row(node: 0, above: [Self.step(2, 2, .pool(0))], below: [under, bend])
        guard let image = Self.render([row], metrics: metrics, rowHeight: rowHeight) else { return }
        func leaving(_ step: GraphStep) -> GraphCurve.Bezier {
            GraphCurve.leaving(fromX: style.laneCenter(step.from), toX: style.laneCenter(step.to), center: rowHeight / 2,
                               height: rowHeight)
        }
        let upper = Self.polyline(leaving(bend)), lower = Self.polyline(leaving(under))
        let bendPoint = CGPoint(x: style.laneCenter(2), y: rowHeight / 2)
        let node = CGPoint(x: style.laneCenter(0), y: rowHeight / 2)
        let halfStroke = metrics.edgeWidth / 2
        var sampled = 0, nearTheBend = 0
        for center in image.pixelCenters(in: Self.bounds(of: leaving(under), outset: metrics.edgeWidth)) {
            // On the lower S's stroke, in the band beside the upper S's stroke, clear of both edges.
            let offset = Self.distance(from: center, to: upper)
            guard Self.distance(from: center, to: lower) <= halfStroke - 0.5,
                  offset >= halfStroke + 0.5, offset <= halfStroke + metrics.crossingGap - 0.5 else { continue }
            #expect(center.distance(to: node) > metrics.crossingNodeClearance, "\(center)")
            sampled += 1
            nearTheBend += center.distance(to: bendPoint) < metrics.crossingNodeClearance ? 1 : 0
            #expect(image.pixel(at: center).isClose(to: Self.background), "\(center): \(image.pixel(at: center))")
        }
        // Some of them closer to the bend than the clearance around a node.
        #expect(sampled > 0 && nearTheBend > 0, "\(sampled) sampled, \(nearTheBend) near the bend")
    }

    /// Checks that every pixel well inside the stroke of the half `row` draws
    /// of `step` as it arrives (centre within half the stroke less 0.5 pt of
    /// its middle) and at least 0.5 pt clear of the stroke of the straight line
    /// in `column` shows the line, not the background: the straight line's
    /// band, drawn after it, left it whole along the way.
    private func expectDrawnWhole(_ step: GraphStep, arrivingIn row: GraphRow, besideStraightIn column: Int,
                                  density: DensityMetrics, sourceLocation: SourceLocation = #_sourceLocation) {
        let metrics = density.graph, rowHeight = density.rowList
        let style = Self.style(metrics)
        guard let image = Self.render([row], metrics: metrics, rowHeight: rowHeight, sourceLocation: sourceLocation)
        else { return }
        let half = GraphCurve.arriving(fromX: style.laneCenter(step.from), toX: style.laneCenter(step.to),
                                       center: rowHeight / 2, height: rowHeight)
        let polyline = Self.polyline(half)
        let halfStroke = metrics.edgeWidth / 2
        var sampled = 0
        for center in image.pixelCenters(in: Self.bounds(of: half, outset: metrics.edgeWidth)) {
            guard Self.distance(from: center, to: polyline) <= halfStroke - 0.5,
                  abs(center.x - style.laneCenter(column)) >= halfStroke + 0.5 else { continue }
            sampled += 1
            let pixel = image.pixel(at: center)
            #expect(!pixel.isClose(to: Self.background), "\(center): \(pixel)", sourceLocation: sourceLocation)
        }
        #expect(sampled >= 10, "only \(sampled) pixels sampled", sourceLocation: sourceLocation)
    }

    // MARK: - Lines through a row's centre

    @Test("At 1x, with the row's centre in the middle of a pixel, a line passing or bending there away from the node shows no notch",
          arguments: [DensityMetrics.regular, .compact], [0, 1, 2])
    func noNotchAtTheCentre(density: DensityMetrics, shape: Int) {
        let metrics = density.graph, spacing = HistoryTableLayout.rowSpacing
        let style = Self.style(metrics)
        // Each with a straight piece beside the centre, the line's body to compare the centre with.
        let (arriving, leaving, straightAbove) = [
            (Self.step(1, 1, .head), Self.step(1, 1, .head), true), // passing straight through
            (Self.step(1, 1, .head), Self.step(1, 2, .head), true), // bending into an S
            (Self.step(2, 1, .head), Self.step(1, 1, .head), false), // landing from an S
        ][shape]
        // And a straight half drawn alone, arriving down column 3: the same colour, at the same horizontal pixel phase.
        let row = Self.row(node: 0, above: [arriving, Self.step(3, 3, .head)], below: [leaving])
        // The canvas as the table sizes it, one pitch (the row and the gap) plus the bleed past each joint: an odd
        // number of points tall, so at 1x its centre, where the halves meet, lies in the middle of a pixel row.
        let size = CGSize(width: style.gutterWidth(lanes: Self.lanes),
                          height: GraphRowGeometry.canvasHeight(pitch: density.rowList + spacing, metrics: metrics))
        #expect(size.height.truncatingRemainder(dividingBy: 2) == 1)
        let canvas = Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))
            GraphRowPainter(style: style, size: size, rowSpacing: spacing).drawSteps(of: row, in: &context)
        }
        guard let image = Self.render(canvas, size: size, scale: 1) else { return }
        // The pixel left of the line's middle: inside the stroke across its whole width in regular, 7/8 of it in
        // compact. Where the halves meet it is as lit as along the straight piece, 6 pt away.
        let x = style.laneCenter(1) - 0.5, center = size.height / 2
        let meeting = image.pixel(at: CGPoint(x: x, y: center))
        let body = image.pixel(at: CGPoint(x: x, y: straightAbove ? center - 6 : center + 6))
        #expect(!body.isClose(to: Self.black), "body \(body)")
        #expect(meeting.isClose(to: body), "\(arriving) into \(leaving): \(meeting) where the line is \(body)")
        if shape == 0 {
            // Passing straight through, the line looks just like a straight half drawn alone.
            let alone = image.pixel(at: CGPoint(x: style.laneCenter(3) - 0.5, y: center - 6))
            #expect(body.isClose(to: alone, tolerance: 2), "\(body) where a half alone is \(alone)")
        }
    }

    // MARK: - Ghosts

    private static let black = Pixel(red: 0, green: 0, blue: 0, alpha: 255)

    /// What a ghost drawn in HEAD's colour (pure blue) at `opacity` shows over black.
    private static func ghostBlue(_ opacity: Double) -> Pixel {
        Pixel(red: 0, green: 0, blue: UInt8((255 * opacity).rounded()), alpha: 255)
    }

    @Test("A ghost line is dashed and translucent, and Increase Contrast makes it opaque",
          arguments: [DensityMetrics.regular, .compact], [0.6, 1.0])
    func ghostStroke(density: DensityMetrics, opacity: Double) {
        let metrics = density.graph, rowHeight = density.rowList
        let style = Self.style(metrics, ghostOpacity: opacity)
        // A ghost line arrives straight down column 1, from the joint above the row to its centre.
        let row = Self.row(node: 0, above: [Self.step(1, 1, .head, stroke: .ghost)])
        guard let image = Self.render([row], metrics: metrics, rowHeight: rowHeight, ghostOpacity: opacity,
                                      background: .black) else { return }
        let period = GraphRowGeometry.dashPeriod(pitch: rowHeight)
        let periods = Int(((rowHeight / 2) / period).rounded())
        #expect(periods >= 2, "\(periods) periods")
        let x = style.laneCenter(1)
        for index in 0..<periods {
            // The middle of the dash, then of the gap after it: the pattern starts with a dash on the joint and
            // runs on, half a period each.
            let dash = CGPoint(x: x, y: (CGFloat(index) + 0.25) * period)
            let gap = CGPoint(x: x, y: (CGFloat(index) + 0.75) * period)
            #expect(image.pixel(at: dash).isClose(to: Self.ghostBlue(opacity)), "dash \(dash): \(image.pixel(at: dash))")
            #expect(image.pixel(at: gap).isClose(to: Self.black), "gap \(gap): \(image.pixel(at: gap))")
        }
    }

    @Test("A ghost S's dash runs on unbroken across the joint between rows and on down the line it lands on, away from a node",
          arguments: [DensityMetrics.regular, .compact], [1, 3, 4])
    func ghostDashAcrossJointAndCentre(density: DensityMetrics, width: Int) {
        let metrics = density.graph, rowHeight = density.rowList, spacing = HistoryTableLayout.rowSpacing
        let pitch = rowHeight + spacing, lanes = width + 1
        let style = Self.style(metrics, ghostOpacity: 1)
        // A ghost merge's own track, as the table lays it out: an S from the merge in column 0 out to column
        // `width`, then straight down that column, through the centre of a row whose node is elsewhere, to the parent.
        let out = Self.step(0, width, .head, stroke: .ghost), track = Self.step(width, width, .head, stroke: .ghost)
        let rows = [Self.row(node: 0, below: [out], lanes: lanes),
                    Self.row(node: 0, above: [out], below: [track], lanes: lanes),
                    Self.row(node: width, above: [track], lanes: lanes)]
        guard let image = Self.render(rows, metrics: metrics, rowHeight: rowHeight, rowSpacing: spacing, lanes: lanes,
                                      ghostOpacity: 1, background: .black) else { return }
        // The dash each piece should have, written out from §4.3: half a period of the straight lines' (half a pitch
        // holds a whole number of them), or of the S halves' own (their arc length holds a whole number of them).
        let period = GraphRowGeometry.dashPeriod(pitch: pitch)
        let half = GraphCurve.leaving(fromX: style.laneCenter(0), toX: style.laneCenter(width), center: 0, height: pitch)
        let length = GraphCurve.arcLength(half)
        let curvePeriod = length / max(1, (length / period).rounded())
        // The line's centreline from node to node, a point every 0.05 pt along it, each with how far along it is.
        let s = GraphCurve.step(fromX: style.laneCenter(0), toX: style.laneCenter(width), top: rowHeight / 2, height: pitch)
        var points: [(point: CGPoint, along: CGFloat)] = [(s.start, 0)]
        for index in 1...8192 {
            let point = GraphCurve.point(on: s, at: CGFloat(index) / 8192), last = points[points.count - 1]
            points.append((point, last.along + last.point.distance(to: point)))
        }
        let bend = points[points.count - 1].along
        for index in 1...Int(pitch * 20) {
            let last = points[points.count - 1]
            points.append((CGPoint(x: last.point.x, y: last.point.y + 0.05), last.along + 0.05))
        }
        // Runs of dash (lit) and gap along it, clear of the nodes at both ends; the first and last are cut short there.
        let clear = metrics.nodeRadius + 1
        let first = points[0].point, last = points[points.count - 1].point
        var runs: [(lit: Bool, start: CGFloat, end: CGFloat)] = []
        for (point, along) in points where point.distance(to: first) > clear && point.distance(to: last) > clear {
            let lit = Int(image.pixel(at: point).blue) >= 128
            if let run = runs.last, run.lit == lit {
                runs[runs.count - 1].end = along
            } else {
                runs.append((lit, along, along))
            }
        }
        #expect(runs.count >= 12, "\(runs.count) runs")
        for run in runs.dropFirst().dropLast() {
            // Half a period each, within half of that either way: no dash or gap cut short, none run into the next.
            let expected = ((run.start + run.end) / 2 < bend ? curvePeriod : period) / 2
            let length = run.end - run.start
            #expect(length > expected / 2 && length < expected * 3 / 2,
                    "\(run.lit ? "dash" : "gap") from \(run.start) to \(run.end) of \(expected) (the S ends at \(bend))")
        }
    }

    @Test("A solid line next to a ghost one keeps its full colour", arguments: [DensityMetrics.regular, .compact])
    func solidLineStaysOpaque(density: DensityMetrics) {
        let metrics = density.graph, rowHeight = density.rowList
        let row = Self.row(node: 0, above: [Self.step(1, 1, .head, stroke: .ghost), Self.step(2, 2, .head)])
        guard let image = Self.render([row], metrics: metrics, rowHeight: rowHeight, background: .black) else { return }
        let point = CGPoint(x: Self.style(metrics).laneCenter(2), y: rowHeight / 4)
        #expect(image.pixel(at: point).isClose(to: Self.ghostBlue(1)), "\(point): \(image.pixel(at: point))")
    }

    @Test("A ghost node is a hollow ring of six dashes at the commit node's size, translucent unless told otherwise",
          arguments: [DensityMetrics.regular, .compact], [0.6, 1.0])
    func ghostNode(density: DensityMetrics, opacity: Double) {
        let metrics = density.graph, rowHeight = density.rowList
        let style = Self.style(metrics, ghostOpacity: opacity)
        let row = Self.row(node: 1, color: .head, isGhost: true)
        // Over black, which is also the node fill, so a stroke over either side of the path's edge reads alike.
        guard let image = Self.render([row], metrics: metrics, rowHeight: rowHeight, ghostOpacity: opacity,
                                      background: .black),
              let overRed = Self.render([row], metrics: metrics, rowHeight: rowHeight, ghostOpacity: opacity)
        else { return }
        let center = CGPoint(x: style.laneCenter(1), y: rowHeight / 2)
        func point(radius: CGFloat, degrees: CGFloat) -> CGPoint {
            CGPoint(x: center.x + radius * cos(degrees * .pi / 180), y: center.y + radius * sin(degrees * .pi / 180))
        }
        // Hollow: where a commit would be filled the node fill shows, not the line colour or the background.
        #expect(image.pixel(at: center).isClose(to: Self.black), "centre: \(image.pixel(at: center))")
        #expect(overRed.pixel(at: center).isClose(to: Self.black), "centre over red: \(overRed.pixel(at: center))")
        // Nothing past the commit node's radius.
        for degrees in stride(from: CGFloat(0), to: 360, by: 15) {
            let outside = image.pixel(at: point(radius: metrics.nodeRadius + 0.6, degrees: degrees))
            #expect(outside.isClose(to: Self.black), "\(degrees)° outside: \(outside)")
        }
        // Round the middle of the 1.5 pt stroke, every 2.5°: it is lit (at least half the dash colour) in six
        // runs, the dashes. A single pixel can straddle the end of a dash on a ring this small, so the test
        // counts runs instead of reading one pixel per dash.
        let lit = stride(from: CGFloat(0), to: 360, by: 2.5).map {
            Int(image.pixel(at: point(radius: metrics.nodeRadius - 0.75, degrees: $0)).blue)
                >= Int(Self.ghostBlue(opacity).blue) / 2
        }
        let runs = lit.indices.filter { lit[$0] && !lit[($0 + lit.count - 1) % lit.count] }.count
        #expect(runs == 6, "\(runs) dashes: \(lit.map { $0 ? "#" : "." }.joined())")
        #expect(lit.contains(false), "no gaps")
    }

    // MARK: - Selection and hover

    @Test("A selected or hovered HEAD's halo and ring are drawn, and stop at the edges of their row",
          arguments: [DensityMetrics.regular, .compact], [true, false])
    func haloStopsAtTheRowEdge(density: DensityMetrics, selected: Bool) {
        let metrics = density.graph, rowHeight = density.rowList, spacing = HistoryTableLayout.rowSpacing
        let style = Self.style(metrics)
        let row = Self.row(node: 1, color: .head)
        // Three rows as the table lays them out, the gap between them included; the middle one is selected or hovered.
        let size = CGSize(width: style.gutterWidth(lanes: Self.lanes), height: 3 * rowHeight + 2 * spacing)
        guard let image = Self.render(ZStack(alignment: .topLeading) {
            Color(red: 1, green: 0, blue: 0)
            VStack(spacing: spacing) {
                ForEach(0..<3, id: \.self) { index in
                    GraphColumnView(row: row, maxLanes: Self.lanes, style: style, rowSpacing: spacing,
                                    isHeadCommit: true, isSelected: selected && index == 1,
                                    isHovered: !selected && index == 1)
                        .frame(height: rowHeight)
                }
            }
        }, size: size) else { return }
        let x = style.laneCenter(1)
        let top = rowHeight + spacing, bottom = top + rowHeight, center = top + rowHeight / 2
        // Drawn: the halo fills out to near the edge; the ring is stroked at the node's outer radius plus its outset.
        let reach = selected ? rowHeight / 2 - 1.5 : metrics.headOuterRadius + metrics.hoverRingOutset
        for y in [center - reach, center + reach] {
            let pixel = image.pixel(at: CGPoint(x: x, y: y))
            #expect(!pixel.isClose(to: Self.background), "\(selected ? "halo" : "ring") at \(y): \(pixel)")
        }
        // Not past the row: neither just beyond its edge nor in the middle of the gap, above and below.
        for y in [top - 0.25, top - spacing / 2, bottom + 0.25, bottom + spacing / 2] {
            let pixel = image.pixel(at: CGPoint(x: x, y: y))
            #expect(pixel.isClose(to: Self.background), "\(selected ? "halo" : "ring") reaches \(y): \(pixel)")
        }
    }

    // MARK: - Geometry, written out independently of the painter

    /// Where the crossing gap must leave lines alone (§5.2): the node, and
    /// where a curve half meets the row's centre beside a straight of its
    /// column on the same side of the centre.
    private static func protectedPoints(of row: GraphRow, style: GraphStyle, rowHeight: CGFloat) -> [CGPoint] {
        let center = rowHeight / 2
        func straight(in column: Int, _ steps: [GraphStep]) -> Bool {
            steps.contains { $0.from == column && $0.to == column }
        }
        return [CGPoint(x: style.laneCenter(row.node.column), y: center)]
            + row.stepsAbove.filter { $0.from != $0.to && straight(in: $0.to, row.stepsAbove) }
                .map { CGPoint(x: style.laneCenter($0.to), y: center) }
            + row.stepsBelow.filter { $0.from != $0.to && straight(in: $0.from, row.stepsBelow) }
                .map { CGPoint(x: style.laneCenter($0.from), y: center) }
    }

    /// The point of `curve`, a half of an S or a whole one, where its x is
    /// `x`, found by bisection: x runs one way from one end to the other.
    private static func point(on curve: GraphCurve.Bezier, atX x: CGFloat) -> CGPoint {
        var low: CGFloat = 0, high: CGFloat = 1
        let rising = curve.end.x > curve.start.x
        for _ in 0..<64 {
            let middle = (low + high) / 2
            if (GraphCurve.point(on: curve, at: middle).x < x) == rising { low = middle } else { high = middle }
        }
        return GraphCurve.point(on: curve, at: (low + high) / 2)
    }

    /// `curve` as 512 straight segments, far closer to it than a pixel.
    private static func polyline(_ curve: GraphCurve.Bezier) -> [CGPoint] {
        (0...512).map { GraphCurve.point(on: curve, at: CGFloat($0) / 512) }
    }

    /// The distance from `point` to the nearest segment of `polyline`.
    private static func distance(from point: CGPoint, to polyline: [CGPoint]) -> CGFloat {
        zip(polyline, polyline.dropFirst()).map { a, b in
            let (dx, dy) = (b.x - a.x, b.y - a.y)
            let t = max(0, min(1, ((point.x - a.x) * dx + (point.y - a.y) * dy) / (dx * dx + dy * dy)))
            return point.distance(to: CGPoint(x: a.x + t * dx, y: a.y + t * dy))
        }.min() ?? .infinity
    }

    /// The box around `curve`'s control points, which holds the whole curve, `outset` larger on every side.
    private static func bounds(of curve: GraphCurve.Bezier, outset: CGFloat) -> CGRect {
        let xs = [curve.start.x, curve.control1.x, curve.control2.x, curve.end.x]
        let ys = [curve.start.y, curve.control1.y, curve.control2.y, curve.end.y]
        return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
            .insetBy(dx: -outset, dy: -outset)
    }
}

// MARK: - Reading pixels

/// One 8-bit RGBA pixel, premultiplied: a transparent one is all zeros.
private struct Pixel: Equatable, CustomStringConvertible {
    let red: UInt8
    let green: UInt8
    let blue: UInt8
    let alpha: UInt8

    /// Whether every channel, alpha included, is within `tolerance` of `other`'s.
    func isClose(to other: Pixel, tolerance: Int = 12) -> Bool {
        abs(Int(red) - Int(other.red)) <= tolerance && abs(Int(green) - Int(other.green)) <= tolerance
            && abs(Int(blue) - Int(other.blue)) <= tolerance && abs(Int(alpha) - Int(other.alpha)) <= tolerance
    }

    var description: String { "rgba(\(red), \(green), \(blue), \(alpha))" }
}

/// A rendered image read back as 8-bit sRGB RGBA, its top row first.
private struct Rendering {
    /// Pixels per point.
    let scale: CGFloat
    let width: Int
    let height: Int
    private let bytes: [UInt8]

    /// Draws `image` into a bitmap of known layout, so its bytes read the same
    /// whatever format the renderer chose. Nil if the bitmap can't be made.
    init?(_ image: CGImage, scale: CGFloat) {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let (width, height) = (image.width, image.height)
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        self.scale = scale
        self.width = width
        self.height = height
        self.bytes = bytes
    }

    /// The pixel that holds `point`, in points from the top-left corner.
    func pixel(at point: CGPoint) -> Pixel {
        let x = min(max(Int((point.x * scale).rounded(.down)), 0), width - 1)
        let y = min(max(Int((point.y * scale).rounded(.down)), 0), height - 1)
        let index = (y * width + x) * 4
        return Pixel(red: bytes[index], green: bytes[index + 1], blue: bytes[index + 2], alpha: bytes[index + 3])
    }

    /// The centre, in points, of every pixel of the image whose centre lies in `rect`.
    func pixelCenters(in rect: CGRect) -> [CGPoint] {
        let columns = max(0, Int((rect.minX * scale).rounded(.down)))...min(width - 1, Int((rect.maxX * scale).rounded(.down)))
        let rows = max(0, Int((rect.minY * scale).rounded(.down)))...min(height - 1, Int((rect.maxY * scale).rounded(.down)))
        return rows.flatMap { y in
            columns.map { x in CGPoint(x: (CGFloat(x) + 0.5) / scale, y: (CGFloat(y) + 0.5) / scale) }
        }.filter { rect.contains($0) }
    }
}

private extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat { hypot(x - other.x, y - other.y) }
}

private extension GraphMetrics {
    /// The same metrics with another crossing gap.
    func withCrossingGap(_ gap: CGFloat) -> GraphMetrics {
        GraphMetrics(laneWidth: laneWidth, firstLaneX: firstLaneX, edgeWidth: edgeWidth, nodeRadius: nodeRadius,
                     nodeGap: nodeGap, crossingGap: gap, crossingNodeClearance: crossingNodeClearance,
                     headOuterRadius: headOuterRadius, headInnerRadius: headInnerRadius, stashSize: stashSize,
                     worktreeRadius: worktreeRadius, selectHaloOutset: selectHaloOutset,
                     selectHaloOpacity: selectHaloOpacity, hoverRingOutset: hoverRingOutset,
                     hoverRingWidth: hoverRingWidth, hoverRingOpacity: hoverRingOpacity, chipHeight: chipHeight)
    }
}
