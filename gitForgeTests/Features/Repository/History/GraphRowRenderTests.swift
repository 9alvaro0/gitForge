import CoreGraphics
import SwiftUI
import Testing
@testable import gitForge

/// Renders graph rows the way the History table stacks them, over a pure red
/// background no line is drawn in, and reads their pixels back: where the
/// crossing gap (§5.2) clears a line, the row's own background shows.
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

    /// Fixed colours, none of them near red, whatever the system accent is.
    private static func style(_ metrics: GraphMetrics) -> GraphStyle {
        GraphStyle(metrics: metrics, accent: .violet, accentColor: Color(red: 0, green: 0, blue: 1), dark: true,
                   nodeFill: .black)
    }

    private static func step(_ from: Int, _ to: Int, _ color: GraphColorRole) -> GraphStep {
        GraphStep(from: from, to: to, color: color, stroke: .solid)
    }

    private static func row(node column: Int, above: [GraphStep] = [], below: [GraphStep] = []) -> GraphRow {
        GraphRow(node: GraphNode(column: column, kind: .commit, color: .pool(2), isGhost: false),
                 stepsAbove: above, stepsBelow: below, width: lanes)
    }

    /// `rows` stacked with no gap, each `rowHeight` tall, over the background.
    private static func render(_ rows: [GraphRow], metrics: GraphMetrics, rowHeight: CGFloat,
                               sourceLocation: SourceLocation = #_sourceLocation) -> Rendering? {
        let style = style(metrics)
        let size = CGSize(width: style.gutterWidth(lanes: lanes), height: rowHeight * CGFloat(rows.count))
        return render(ZStack(alignment: .topLeading) {
            Color(red: 1, green: 0, blue: 0)
            VStack(spacing: 0) {
                ForEach(rows.indices, id: \.self) { index in
                    GraphColumnView(row: rows[index], maxLanes: lanes, style: style, rowSpacing: 0)
                        .frame(height: rowHeight)
                }
            }
        }, size: size, sourceLocation: sourceLocation)
    }

    /// `view`, framed to `size` and rendered at twice the point size; nil,
    /// with an issue recorded, if the renderer gives no image of that size.
    private static func render(_ view: some View, size: CGSize,
                               sourceLocation: SourceLocation = #_sourceLocation) -> Rendering? {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
        renderer.scale = 2
        guard let image = renderer.cgImage, let rendering = Rendering(image, scale: 2),
              rendering.width == Int(size.width * 2), rendering.height == Int(size.height * 2) else {
            Issue.record("No \(size) image rendered at 2x", sourceLocation: sourceLocation)
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

    // MARK: - Geometry, written out independently of the painter

    /// Where the crossing gap must leave lines alone (§5.2): the node, and
    /// where each curve half meets the row's centre.
    private static func protectedPoints(of row: GraphRow, style: GraphStyle, rowHeight: CGFloat) -> [CGPoint] {
        let center = rowHeight / 2
        return [CGPoint(x: style.laneCenter(row.node.column), y: center)]
            + row.stepsAbove.filter { $0.from != $0.to }.map { CGPoint(x: style.laneCenter($0.to), y: center) }
            + row.stepsBelow.filter { $0.from != $0.to }.map { CGPoint(x: style.laneCenter($0.from), y: center) }
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
