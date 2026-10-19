import SwiftUI

/// The drag HUD's mini graph: what the graph looks like after the drop,
/// drawn schematically (at most three dots per run; the caption has the
/// counts). Merge / rebase are both drawn for a branch-on-branch drop,
/// since the choice comes after it.
struct BranchDropGraphPreview: View {
    let preview: BranchDropPreview
    let source: String
    let target: String

    var body: some View {
        switch preview.kind {
        case let .integrate(sourceOnly, targetOnly):
            HStack(alignment: .top, spacing: Spacing.s16) {
                PreviewColumn(title: "Merge", sketch: .merge(source: sourceOnly, target: targetOnly),
                              caption: BranchDropPreview.mergeCaption(sourceOnly: sourceOnly, targetOnly: targetOnly,
                                                                      source: source, target: target))
                PreviewColumn(title: "Rebase", sketch: .rebase(source: sourceOnly, target: targetOnly),
                              caption: BranchDropPreview.rebaseCaption(sourceOnly: sourceOnly, targetOnly: targetOnly,
                                                                       source: source, target: target))
            }
        case let .move(dropped, gained):
            PreviewColumn(title: nil, sketch: .move(dropped: dropped, gained: gained),
                          caption: BranchDropPreview.moveCaption(dropped: dropped, gained: gained, branch: source))
        }
    }
}

private struct PreviewColumn: View {
    let title: String?
    let sketch: GraphSketch
    let caption: String

    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s4) {
            if let title {
                Text(title)
                    .textRole(.caption, weight: .semibold)
                    .foregroundStyle(theme.colors.textSecondary)
            }
            SketchCanvas(sketch: sketch)
            Text(caption)
                .textRole(.caption)
                .foregroundStyle(theme.colors.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([title, caption].compactMap { $0 }.joined(separator: ": "))
    }
}

/// Dots and edges on two lanes (0 = top, the line that ends up holding the
/// result; 1 = bottom).
struct GraphSketch: Equatable {
    enum Style: Equatable {
        /// Commits the drop doesn't touch.
        case plain
        /// The dragged branch's commits.
        case source
        /// Commits left behind (old positions).
        case ghost
    }

    struct Node: Equatable {
        let column: Int
        let lane: Int
        let style: Style
        /// Where the branch ends up (bigger dot).
        var isTip = false
        /// Where the branch was (hollow).
        var isOldTip = false
    }

    struct Edge: Equatable {
        let from: Int
        let to: Int
        let style: Style
    }

    var nodes: [Node] = []
    var edges: [Edge] = []

    static let maxRun = 3

    /// Appends a node joined to `previous`; returns its index.
    @discardableResult
    mutating func add(_ node: Node, after previous: Int?, edge: Style? = nil) -> Int {
        nodes.append(node)
        let index = nodes.count - 1
        if let previous { edges.append(Edge(from: previous, to: index, style: edge ?? node.style)) }
        return index
    }

    /// A run of up to `maxRun` dots on `lane` after `start`.
    mutating func run(_ count: Int, lane: Int, from start: Int, column: Int, style: Style) -> (last: Int, column: Int) {
        var last = start
        var column = column
        for _ in 0..<min(count, Self.maxRun) {
            column += 1
            last = add(Node(column: column, lane: lane, style: style), after: last)
        }
        return (last, column)
    }

    static func merge(source: Int, target: Int) -> GraphSketch {
        var sketch = GraphSketch()
        let base = sketch.add(Node(column: 0, lane: 0, style: .plain), after: nil)
        guard source > 0 else {
            _ = sketch.run(max(target, 1), lane: 0, from: base, column: 0, style: .plain)
            return sketch
        }
        if target == 0 {
            // Fast-forward: the target just moves up the source's line.
            let run = sketch.run(source, lane: 0, from: base, column: 0, style: .source)
            sketch.nodes[run.last].isTip = true
            return sketch
        }
        let main = sketch.run(target, lane: 0, from: base, column: 0, style: .plain)
        let side = sketch.run(source, lane: 1, from: base, column: 0, style: .source)
        let merge = sketch.add(Node(column: max(main.column, side.column) + 1, lane: 0, style: .source, isTip: true),
                               after: main.last, edge: .plain)
        sketch.edges.append(Edge(from: side.last, to: merge, style: .source))
        return sketch
    }

    static func rebase(source: Int, target: Int) -> GraphSketch {
        var sketch = GraphSketch()
        let base = sketch.add(Node(column: 0, lane: 0, style: .plain), after: nil)
        guard target > 0 else {
            // Already on top: nothing moves.
            let run = sketch.run(max(source, 1), lane: 0, from: base, column: 0, style: .source)
            sketch.nodes[run.last].isTip = true
            return sketch
        }
        let main = sketch.run(target, lane: 0, from: base, column: 0, style: .plain)
        if source > 0 {
            let old = sketch.run(source, lane: 1, from: base, column: 0, style: .ghost)
            sketch.nodes[old.last].isOldTip = true
        }
        let replayed = sketch.run(source, lane: 0, from: main.last, column: main.column, style: .source)
        sketch.nodes[replayed.last].isTip = true
        return sketch
    }

    static func move(dropped: Int, gained: Int) -> GraphSketch {
        var sketch = GraphSketch()
        if gained == 0 {
            // Back along its own line: what's after the new tip stays behind.
            let tip = sketch.add(Node(column: 0, lane: 0, style: .source, isTip: true), after: nil)
            let left = sketch.run(dropped, lane: 0, from: tip, column: 0, style: .ghost)
            sketch.nodes[left.last].isOldTip = true
            return sketch
        }
        if dropped == 0 {
            // Forward: fast-forward along the target's line.
            let old = sketch.add(Node(column: 0, lane: 0, style: .plain, isOldTip: true), after: nil)
            let run = sketch.run(gained, lane: 0, from: old, column: 0, style: .source)
            sketch.nodes[run.last].isTip = true
            return sketch
        }
        let base = sketch.add(Node(column: 0, lane: 0, style: .plain), after: nil)
        let new = sketch.run(gained, lane: 0, from: base, column: 0, style: .source)
        sketch.nodes[new.last].isTip = true
        let old = sketch.run(dropped, lane: 1, from: base, column: 0, style: .ghost)
        sketch.nodes[old.last].isOldTip = true
        return sketch
    }
}

private struct SketchCanvas: View {
    let sketch: GraphSketch

    @Environment(\.appTheme) private var theme

    static let step: CGFloat = 18
    static let laneY: [CGFloat] = [9, 27]
    static let inset: CGFloat = 7

    var body: some View {
        let columns = (sketch.nodes.map(\.column).max() ?? 0) + 1
        let lanes = sketch.nodes.contains { $0.lane == 1 } ? 2 : 1
        Canvas { context, _ in
            for edge in sketch.edges {
                let from = point(sketch.nodes[edge.from])
                let to = point(sketch.nodes[edge.to])
                var path = Path()
                path.move(to: from)
                if from.y == to.y {
                    path.addLine(to: to)
                } else {
                    let mid = (from.x + to.x) / 2
                    path.addCurve(to: to, control1: CGPoint(x: mid, y: from.y), control2: CGPoint(x: mid, y: to.y))
                }
                let dash: [CGFloat] = edge.style == .ghost ? [3, 3] : []
                context.stroke(path, with: .color(color(edge.style)), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: dash))
            }
            for node in sketch.nodes {
                let center = point(node)
                let radius: CGFloat = node.isTip ? 5 : 3.5
                let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
                if node.isOldTip {
                    context.fill(Path(ellipseIn: rect), with: .color(theme.colors.bgElevated))
                    context.stroke(Path(ellipseIn: rect), with: .color(color(node.style)), lineWidth: 1.5)
                } else {
                    context.fill(Path(ellipseIn: rect), with: .color(color(node.style)))
                }
            }
        }
        .frame(width: Self.inset * 2 + CGFloat(columns - 1) * Self.step,
               height: (Self.laneY[lanes - 1]) + Self.inset + 2)
        .accessibilityHidden(true)
    }

    private func point(_ node: GraphSketch.Node) -> CGPoint {
        CGPoint(x: Self.inset + CGFloat(node.column) * Self.step, y: Self.laneY[node.lane])
    }

    private func color(_ style: GraphSketch.Style) -> Color {
        switch style {
        case .plain: theme.colors.textTertiary
        case .source: theme.colors.accent
        case .ghost: theme.colors.textQuaternary
        }
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    VStack(alignment: .leading, spacing: 24) {
        BranchDropGraphPreview(preview: BranchDropPreview(kind: .integrate(sourceOnly: 3, targetOnly: 2)),
                               source: "feature/lanes", target: "main")
        BranchDropGraphPreview(preview: BranchDropPreview(kind: .integrate(sourceOnly: 2, targetOnly: 0)),
                               source: "feature/lanes", target: "main")
        BranchDropGraphPreview(preview: BranchDropPreview(kind: .move(dropped: 2, gained: 0)),
                               source: "feature/lanes", target: "a3f9c21")
        BranchDropGraphPreview(preview: BranchDropPreview(kind: .move(dropped: 1, gained: 3)),
                               source: "feature/lanes", target: "a3f9c21")
    }
    .frame(width: 420)
    .padding(40)
    .background(theme.colors.bgContent)
    .appTheme(theme)
}
