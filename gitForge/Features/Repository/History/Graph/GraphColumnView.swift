import SwiftUI

/// Everything a graph row needs to paint itself (graph v3 spec §5), resolved
/// once per table render instead of once per row or per step. The table
/// rebuilds it on every render, so a new accent or appearance always lands.
nonisolated struct GraphStyle: Equatable, Sendable {
    let metrics: GraphMetrics
    let accent: AccentSwatch
    /// `theme.colors.accent`, the colour of HEAD's line.
    let accentColor: Color
    let dark: Bool
    /// Fill behind hollow nodes; matches the table background.
    let nodeFill: Color
    /// How opaque the line and node of a ghost, a commit that only exists on
    /// the server, are drawn (§4.3).
    let ghostOpacity: Double
    /// Every role's colour, resolved here so drawing a step is a lookup and
    /// never rebuilds the pool.
    private let palette: Palette

    init(metrics: GraphMetrics = .regular, accent: AccentSwatch = .violet,
         accentColor: Color = .accentColor, dark: Bool = true, nodeFill: Color = .black,
         ghostOpacity: Double = GraphStyle.translucentGhostOpacity) {
        self.metrics = metrics
        self.accent = accent
        self.accentColor = accentColor
        self.dark = dark
        self.nodeFill = nodeFill
        self.ghostOpacity = ghostOpacity
        palette = Palette(accent: accent, accentColor: accentColor, dark: dark)
    }

    /// The colour a role is drawn with: the same as
    /// `LaneColors.color(for:accent:accentColor:dark:)`, without its per-call cost.
    func color(for role: GraphColorRole) -> Color {
        switch role {
        case .head: palette.head
        case .main: palette.main
        case .develop: palette.develop
        case .stash, .neutral: palette.muted
        case .pool(let index): palette.poolColor(index)
        }
    }

    /// How translucent ghosts are (§5.3).
    static let translucentGhostOpacity = 0.6

    /// The opacity ghosts are drawn with: translucent, unless Increase
    /// Contrast or Reduce Transparency is on, which make them opaque (§5.7).
    /// Their dashes and hollow node still tell them apart.
    static func ghostOpacity(increasedContrast: Bool, reduceTransparency: Bool) -> Double {
        increasedContrast || reduceTransparency ? 1 : translucentGhostOpacity
    }

    func laneCenter(_ lane: Int) -> CGFloat {
        metrics.firstLaneX + CGFloat(lane) * metrics.laneWidth
    }

    /// Width the gutter needs for `lanes` lanes, with the same margin on both sides.
    func gutterWidth(lanes: Int) -> CGFloat {
        2 * metrics.firstLaneX + CGFloat(max(lanes, 1) - 1) * metrics.laneWidth
    }

    nonisolated private struct Palette: Equatable, Sendable {
        let head: Color
        let main: Color
        let develop: Color
        /// Stashes and lines nobody owns.
        let muted: Color
        /// In `GraphColorRole.pool` index order.
        let pool: [Color]

        init(accent: AccentSwatch, accentColor: Color, dark: Bool) {
            func resolve(_ role: GraphColorRole) -> Color {
                LaneColors.color(for: role, accent: accent, accentColor: accentColor, dark: dark)
            }
            head = resolve(.head)
            main = resolve(.main)
            develop = resolve(.develop)
            muted = resolve(.neutral)
            pool = LaneColors.pool(accent: accent).map {
                LaneColors.color(.lane($0), dark: dark, accent: accentColor)
            }
        }

        /// Wraps like `LaneColors.color(for:)`: the engine's indices can briefly
        /// outrun a smaller pool after the accent changes, until the graph
        /// recomputes with the new palette size.
        func poolColor(_ index: Int) -> Color {
            guard !pool.isEmpty else { return muted }
            return pool[((index % pool.count) + pool.count) % pool.count]
        }
    }
}

/// One row of the commit graph: its halves of the steps that cross it, then
/// the commit's node (§5.1, §5.3).
struct GraphColumnView: View {
    let row: GraphRow
    let maxLanes: Int
    var style = GraphStyle()
    /// Gap between this row and its neighbours (`HistoryTableLayout.rowSpacing`).
    /// The lines of adjacent rows join in the middle of the gap.
    var rowSpacing: CGFloat = 0
    var isHeadCommit = false
    var isSelected = false
    var isHovered = false
    /// The row is drawn translucent (`CommitRow` dims it), so its halves
    /// stop on the joints instead of overlapping the neighbours'
    /// (`GraphRowGeometry.overlapsJoints`).
    var isDimmed = false

    var body: some View {
        let style = style
        let row = row
        let node = GraphNodeStyle.for(row, isHeadCommit: isHeadCommit)
        let isSelected = isSelected
        let isHovered = isHovered
        let overlapsJoints = !isDimmed
        let rowSpacing = rowSpacing
        Canvas { context, size in
            let painter = GraphRowPainter(style: style, size: size, overlapsJoints: overlapsJoints,
                                          rowSpacing: rowSpacing)
            painter.drawSteps(of: row, in: &context)
            painter.drawNode(row.node, as: node, isSelected: isSelected, isHovered: isHovered, in: &context)
        }
        // Centred on the row and one row pitch tall plus the bleed past each
        // joint: the layout keeps the row's height, the canvas overhangs half
        // the gap and the bleed on each side.
        .padding(.vertical, -(rowSpacing / 2 + GraphRowGeometry.bleed(for: style.metrics)))
        .frame(width: style.gutterWidth(lanes: maxLanes), alignment: .leading)
    }
}

/// Paints one graph row into a `Canvas` one row pitch tall plus the bleed
/// past each joint (`GraphRowGeometry`): the row's halves of its steps, then
/// its node.
///
/// `nonisolated` because the canvas renders off the main actor. Nothing here
/// allocates per step beyond the step's own path, which serves both its
/// crossing band and its stroke, and a dash pattern when a dashed half's
/// period is not the one before it. Only a row with an S and a crossing gap
/// draws into a layer of its own.
nonisolated struct GraphRowPainter {
    let style: GraphStyle
    let size: CGSize
    /// `GraphRowGeometry.overlapsJoints`.
    var overlapsJoints = true
    /// `GraphRowGeometry.rowSpacing`.
    var rowSpacing: CGFloat = 0

    /// Dash of the stash node's square.
    private static let stashNodeDash: [CGFloat] = [2.5, 2]

    /// Stroke width of the ghost node's ring.
    private static let ghostNodeWidth: CGFloat = 1.5

    /// The row's centre, where its node sits.
    private var center: CGFloat { size.height / 2 }

    /// The row's halves in the geometry's order (`GraphRowGeometry.forEachSegment`),
    /// each erasing first a band around itself from the lines the row drew
    /// before it, so that where it crosses one, the row's background shows
    /// through on either side of it (§5.2).
    func drawSteps(of row: GraphRow, in context: inout GraphicsContext) {
        let geometry = GraphRowGeometry(style: style, size: size, overlapsJoints: overlapsJoints,
                                        rowSpacing: rowSpacing)
        // Without an S, the row's straight halves lie in their own columns,
        // 12 pt or more apart, and cross nothing; without a gap there is no
        // band. Either way there is nothing to erase, and the row draws
        // straight into the context, with no layer.
        guard style.metrics.crossingGap > 0, Self.hasCurve(row) else {
            strokeSteps(of: row, geometry: geometry, eraser: nil, in: &context)
            return
        }
        // Every half goes into one layer, and the band erases only in it:
        // what the row drew before, never the row's background (its
        // selection, hover or drop highlight) behind the canvas.
        context.drawLayer { layer in
            let eraser = crossingEraser(for: row, geometry: geometry, in: layer)
            strokeSteps(of: row, geometry: geometry, eraser: eraser, in: &layer)
        }
    }

    /// Whether any step of `row` changes column, so that the row draws an S.
    private static func hasCurve(_ row: GraphRow) -> Bool {
        row.stepsAbove.contains { $0.from != $0.to } || row.stepsBelow.contains { $0.from != $0.to }
    }

    /// Strokes the row's halves into `context`, each after its band, when
    /// there is an `eraser` (`crossingEraser`).
    private func strokeSteps(of row: GraphRow, geometry: GraphRowGeometry, eraser: GraphicsContext?,
                             in context: inout GraphicsContext) {
        let metrics = style.metrics
        let edge = metrics.edgeWidth
        // Butt caps: a half ends flat where the next one starts, on a joint
        // or at the row's centre under the node (a line that carries on
        // through the centre is one path), and the canvas no longer clips a
        // cap that would reach past a joint. Round caps would also eat the
        // gaps of a dash.
        let solid = StrokeStyle(lineWidth: edge, lineCap: .butt, lineJoin: .round)
        // The band is the stroke widened by the gap on each side, and stays
        // whole under a dashed stroke. Butt caps too, so it ends where the
        // half does.
        let band = StrokeStyle(lineWidth: edge + 2 * metrics.crossingGap, lineCap: .butt, lineJoin: .round)
        // A dashed half (a stash's side step, a ghost line) is a dash and a gap
        // of half its period each, the period the geometry gives it, from its
        // start: it holds a whole number of them, so it ends with a complete
        // gap and the next half, in this row or the next, starts with a dash.
        // The pattern is built again only when the period changes: the
        // straight halves share one, the halves of S curves as wide another.
        var dash: [CGFloat] = []
        let opacity = context.opacity
        geometry.forEachSegment(of: row) { segment, step, dashPeriod in
            let path = segment.path
            eraser?.stroke(path, with: .color(.black), style: band)
            let shading = GraphicsContext.Shading.color(style.color(for: step.color))
            guard dashPeriod > 0 else {
                context.stroke(path, with: shading, style: solid)
                return
            }
            if dash.first != dashPeriod / 2 { dash = [dashPeriod / 2, dashPeriod / 2] }
            let dashed = StrokeStyle(lineWidth: edge, lineCap: .butt, lineJoin: .round, dash: dash)
            // A ghost is translucent. The context's opacity does it, for this
            // stroke only, instead of building a translucent colour per step.
            guard step.stroke == .ghost else {
                context.stroke(path, with: shading, style: dashed)
                return
            }
            context.opacity = opacity * style.ghostOpacity
            context.stroke(path, with: shading, style: dashed)
            context.opacity = opacity
        }
    }

    /// A copy of `layer` that erases whatever it strokes, except within
    /// `crossingNodeClearance` of the points where the row's lines meet
    /// (`GraphRowGeometry.forEachCrossingClearanceCenter`), so they join
    /// cleanly. Built once per row that has a crossing gap, with the row's
    /// one clearance path.
    private func crossingEraser(for row: GraphRow, geometry: GraphRowGeometry,
                                in layer: GraphicsContext) -> GraphicsContext {
        let radius = style.metrics.crossingNodeClearance
        var clearance = Path()
        geometry.forEachCrossingClearanceCenter(of: row) { center in
            clearance.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius,
                                            width: 2 * radius, height: 2 * radius))
        }
        var eraser = layer
        // Non-zero fill, so circles that overlap (or come twice) make one
        // region; inverted, the eraser acts only outside it.
        eraser.clip(to: clearance, options: .inverse)
        eraser.blendMode = .destinationOut
        return eraser
    }

    /// The node on top of the steps (spec v2 §4.5). Selection gets a soft halo
    /// in the node's colour, hover a thin ring; neither reaches past the edge
    /// of the row (`GraphRowGeometry.haloRadius(outer:)`).
    func drawNode(_ node: GraphNode, as shape: GraphNodeStyle, isSelected: Bool, isHovered: Bool,
                  in context: inout GraphicsContext) {
        let m = style.metrics
        let color = style.color(for: node.color)
        let nodeCenter = CGPoint(x: style.laneCenter(node.column), y: center)
        let outer: CGFloat = switch shape {
        case .head: m.headOuterRadius
        case .stash: m.stashSize / 2
        case .commit, .merge, .ghost: m.nodeRadius
        }
        func circle(_ r: CGFloat) -> Path {
            Path(ellipseIn: CGRect(x: nodeCenter.x - r, y: nodeCenter.y - r, width: r * 2, height: r * 2))
        }
        let geometry = GraphRowGeometry(style: style, size: size, overlapsJoints: overlapsJoints,
                                        rowSpacing: rowSpacing)
        if isSelected {
            context.fill(circle(geometry.haloRadius(outer: outer)), with: .color(color.opacity(m.selectHaloOpacity)))
        } else if isHovered {
            context.stroke(circle(geometry.hoverRingRadius(outer: outer)),
                           with: .color(color.opacity(m.hoverRingOpacity)),
                           lineWidth: m.hoverRingWidth)
        }
        switch shape {
        case .commit:
            context.fill(circle(m.nodeRadius), with: .color(color))
        case .merge:
            let ring = circle(m.nodeRadius - m.edgeWidth / 2)
            context.fill(ring, with: .color(style.nodeFill))
            context.stroke(ring, with: .color(color), lineWidth: m.edgeWidth)
        case .head:
            let ring = circle(m.headOuterRadius - 0.75)
            context.fill(ring, with: .color(style.nodeFill))
            context.stroke(ring, with: .color(color), lineWidth: 1.5)
            context.fill(circle(m.headInnerRadius), with: .color(color))
        case .ghost:
            // The commit node's outline, hollow and dashed (§5.3): the path
            // runs along the middle of the stroke, so the ring's outer edge is
            // the commit node's radius. Six equal dashes round it.
            let width = Self.ghostNodeWidth
            let radius = m.nodeRadius - width / 2
            let dash = 2 * .pi * radius / 12
            let ring = circle(radius)
            context.fill(ring, with: .color(style.nodeFill))
            context.stroke(ring, with: .color(color.opacity(style.ghostOpacity)),
                           style: StrokeStyle(lineWidth: width, dash: [dash, dash]))
        case .stash:
            let side = m.stashSize
            let square = Path(
                roundedRect: CGRect(x: nodeCenter.x - side / 2, y: nodeCenter.y - side / 2, width: side, height: side),
                cornerRadius: GraphMetrics.squareMarkRadius
            )
            context.fill(square, with: .color(style.nodeFill))
            context.stroke(square, with: .color(color), style: StrokeStyle(lineWidth: 1.5, dash: Self.stashNodeDash))
        }
    }
}

#Preview {
    let rows = [GraphRow].previewSamples
    // Spaced like the History table, so the lines cross the gaps between rows.
    // The right-hand copy is dimmed the way a search dims its misses.
    HStack(spacing: 24) {
        ForEach([false, true], id: \.self) { dimmed in
            VStack(spacing: HistoryTableLayout.rowSpacing) {
                ForEach(rows.indices, id: \.self) { index in
                    GraphColumnView(row: rows[index], maxLanes: 2, rowSpacing: HistoryTableLayout.rowSpacing,
                                    isHeadCommit: index == 0, isSelected: index == 3, isDimmed: dimmed)
                        .frame(height: 28)
                        .opacity(dimmed ? 0.35 : 1)
                }
            }
        }
    }
    .padding()
    .background(Color.black)
}

#Preview("Ghosts") {
    // Commits that only exist on the server: a dashed line and a hollow dashed
    // node, a merge too. The right-hand copy is what Increase Contrast and
    // Reduce Transparency make of them: opaque, still dashed and hollow.
    let head = GraphStep(from: 0, to: 0, color: .head, stroke: .solid)
    let line = GraphStep(from: 1, to: 1, color: .pool(0), stroke: .ghost)
    let join = GraphStep(from: 1, to: 0, color: .pool(0), stroke: .ghost)
    let rows = [
        GraphRow(node: GraphNode(column: 1, kind: .commit, color: .pool(0), isGhost: true),
                 stepsAbove: [], stepsBelow: [head, line], width: 2),
        GraphRow(node: GraphNode(column: 1, kind: .merge, color: .pool(0), isGhost: true),
                 stepsAbove: [head, line], stepsBelow: [head, join], width: 2),
        GraphRow(node: GraphNode(column: 0, kind: .commit, color: .head, isGhost: false),
                 stepsAbove: [head, join], stepsBelow: [head], width: 2),
    ]
    HStack(spacing: 24) {
        ForEach([GraphStyle.translucentGhostOpacity, 1], id: \.self) { opacity in
            VStack(spacing: HistoryTableLayout.rowSpacing) {
                ForEach(rows.indices, id: \.self) { index in
                    GraphColumnView(row: rows[index], maxLanes: 2, style: GraphStyle(ghostOpacity: opacity),
                                    rowSpacing: HistoryTableLayout.rowSpacing, isSelected: index == 1)
                        .frame(height: 28)
                }
            }
        }
    }
    .padding()
    .background(Color.black)
}

#Preview("Wide curve joints") {
    // An S three columns wide, then one two columns back, in both densities:
    // the joints in the middle of the gaps show the curve unbroken.
    let out = GraphStep(from: 0, to: 3, color: .pool(0), stroke: .solid)
    let back = GraphStep(from: 3, to: 1, color: .pool(1), stroke: .solid)
    let rows = [
        GraphRow(node: GraphNode(column: 0, kind: .commit, color: .head, isGhost: false),
                 stepsAbove: [], stepsBelow: [out], width: 4),
        GraphRow(node: GraphNode(column: 3, kind: .commit, color: .pool(0), isGhost: false),
                 stepsAbove: [out], stepsBelow: [back], width: 4),
        GraphRow(node: GraphNode(column: 1, kind: .commit, color: .pool(1), isGhost: false),
                 stepsAbove: [back], stepsBelow: [], width: 4),
    ]
    HStack(alignment: .top, spacing: 24) {
        ForEach([DensityMetrics.regular, .compact], id: \.rowList) { density in
            VStack(spacing: HistoryTableLayout.rowSpacing) {
                ForEach(rows.indices, id: \.self) { index in
                    GraphColumnView(row: rows[index], maxLanes: 4, style: GraphStyle(metrics: density.graph),
                                    rowSpacing: HistoryTableLayout.rowSpacing)
                        .frame(height: density.rowList)
                }
            }
        }
    }
    .padding()
    .background(Color.black)
}
