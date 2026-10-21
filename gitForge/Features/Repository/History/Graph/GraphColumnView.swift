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
    /// Every role's colour, resolved here so drawing a step is a lookup and
    /// never rebuilds the pool.
    private let palette: Palette

    init(metrics: GraphMetrics = .regular, accent: AccentSwatch = .violet,
         accentColor: Color = .accentColor, dark: Bool = true, nodeFill: Color = .black) {
        self.metrics = metrics
        self.accent = accent
        self.accentColor = accentColor
        self.dark = dark
        self.nodeFill = nodeFill
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
    var isHeadCommit = false
    var isSelected = false
    var isHovered = false

    var body: some View {
        let style = style
        let row = row
        let node = GraphNodeStyle.for(row, isHeadCommit: isHeadCommit)
        let isSelected = isSelected
        let isHovered = isHovered
        Canvas { context, size in
            let painter = GraphRowPainter(style: style, size: size)
            painter.drawSteps(of: row, in: &context)
            painter.drawNode(row.node, as: node, isSelected: isSelected, isHovered: isHovered, in: &context)
        }
        .frame(width: style.gutterWidth(lanes: maxLanes), alignment: .leading)
    }
}

/// Paints one graph row into a `Canvas`. Every step runs from one row centre
/// to the next and both rows draw half of it: this row draws the arriving
/// half of each `stepsAbove` (top edge to centre) and the leaving half of each
/// `stepsBelow` (centre to bottom edge), and the halves meet on the boundary.
///
/// `nonisolated` because the canvas renders off the main actor. Nothing here
/// allocates per step beyond the step's own path.
nonisolated struct GraphRowPainter {
    let style: GraphStyle
    let size: CGSize

    /// Dash of the side step from a stash into its commit.
    private static let stashDash: [CGFloat] = [3, 3]
    /// Dash of the stash node's square.
    private static let stashNodeDash: [CGFloat] = [2.5, 2]

    private var center: CGFloat { size.height / 2 }

    /// Curves first, then the straight segments, so a line passing through
    /// stays on top of the curves that cross it.
    func drawSteps(of row: GraphRow, in context: inout GraphicsContext) {
        let edge = style.metrics.edgeWidth
        let solid = StrokeStyle(lineWidth: edge, lineCap: .round, lineJoin: .round)
        // Butt caps: round caps would eat the gaps of a 3–3 dash.
        let dashed = StrokeStyle(lineWidth: edge, lineCap: .butt, lineJoin: .round, dash: Self.stashDash)

        func stroke(_ path: Path, _ step: GraphStep) {
            // `.ghost` is drawn solid until its own style lands (G2).
            context.stroke(path, with: .color(style.color(for: step.color)),
                           style: step.stroke == .stash ? dashed : solid)
        }

        for step in row.stepsAbove where step.from != step.to {
            stroke(curve(GraphCurve.arriving(fromX: style.laneCenter(step.from), toX: style.laneCenter(step.to),
                                             center: center, height: size.height)), step)
        }
        for step in row.stepsBelow where step.from != step.to {
            stroke(curve(GraphCurve.leaving(fromX: style.laneCenter(step.from), toX: style.laneCenter(step.to),
                                            center: center, height: size.height)), step)
        }
        for step in row.stepsAbove where step.from == step.to {
            stroke(vertical(at: style.laneCenter(step.to), from: 0, to: center), step)
        }
        for step in row.stepsBelow where step.from == step.to {
            stroke(vertical(at: style.laneCenter(step.from), from: center, to: size.height), step)
        }
    }

    /// The node on top of the steps (spec v2 §4.5). Selection gets a soft halo
    /// in the node's colour, hover a thin ring.
    func drawNode(_ node: GraphNode, as shape: GraphNodeStyle, isSelected: Bool, isHovered: Bool,
                  in context: inout GraphicsContext) {
        let m = style.metrics
        let color = style.color(for: node.color)
        let nodeCenter = CGPoint(x: style.laneCenter(node.column), y: center)
        let outer: CGFloat = switch shape {
        case .head: m.headOuterRadius
        case .stash: m.stashSize / 2
        case .commit, .merge: m.nodeRadius
        }
        func circle(_ r: CGFloat) -> Path {
            Path(ellipseIn: CGRect(x: nodeCenter.x - r, y: nodeCenter.y - r, width: r * 2, height: r * 2))
        }
        if isSelected {
            context.fill(circle(outer + m.selectHaloOutset), with: .color(color.opacity(m.selectHaloOpacity)))
        } else if isHovered {
            context.stroke(circle(outer + m.hoverRingOutset),
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

    private func curve(_ bezier: GraphCurve.Bezier) -> Path {
        var path = Path()
        path.move(to: bezier.start)
        path.addCurve(to: bezier.end, control1: bezier.control1, control2: bezier.control2)
        return path
    }

    private func vertical(at x: CGFloat, from top: CGFloat, to bottom: CGFloat) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: x, y: top))
        path.addLine(to: CGPoint(x: x, y: bottom))
        return path
    }
}

#Preview {
    let rows = [GraphRow].previewSamples
    VStack(spacing: 0) {
        ForEach(rows.indices, id: \.self) { index in
            GraphColumnView(row: rows[index], maxLanes: 2, isHeadCommit: index == 0, isSelected: index == 3)
                .frame(height: 28)
        }
    }
    .padding()
    .background(Color.black)
}
