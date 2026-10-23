import SwiftUI

/// The start of the connector under the Uncommitted changes row's square (§5.5): `step`'s
/// leaving half, painted by `GraphRowPainter` as a graph row would, over the same canvas
/// (one row pitch plus the bleed, centred on the row), with the square's area left clear so
/// its inside shows the row's background. The square itself stays the row's.
struct UncommittedConnectorView: View {
    let step: GraphStep
    let maxLanes: Int
    var style = GraphStyle()
    var rowSpacing: CGFloat = 0
    /// Side of the square it starts under, centred on lane 0 and the row's centre.
    var squareSide: CGFloat = 9

    var body: some View {
        let style = style
        let rowSpacing = rowSpacing
        let squareSide = squareSide
        // A row whose only step is the connector leaving it. Its node is never
        // drawn: the square stands in for it.
        let row = GraphRow(node: GraphNode(column: step.from, kind: .commit, color: step.color, isGhost: false),
                           stepsAbove: [], stepsBelow: [step], width: maxLanes)
        Canvas { context, size in
            let square = CGRect(x: style.laneCenter(0) - squareSide / 2, y: size.height / 2 - squareSide / 2,
                                width: squareSide, height: squareSide)
            context.clip(to: Path(square), options: .inverse)
            GraphRowPainter(style: style, size: size, rowSpacing: rowSpacing).drawSteps(of: row, in: &context)
        }
        // Framed like `GraphColumnView`: the layout keeps the row's height,
        // the canvas overhangs half the gap and the bleed on each side.
        .padding(.vertical, -(rowSpacing / 2 + GraphRowGeometry.bleed(for: style.metrics)))
        .frame(width: style.gutterWidth(lanes: maxLanes), alignment: .leading)
    }
}

#Preview {
    // The Uncommitted changes row's square, with the connector starting under it, then the rows down to HEAD's
    // commit: one with a stash beside the connector, then HEAD's, in both densities. The square is drawn here as
    // `UncommittedRow` draws it.
    @Previewable @State var theme = AppTheme()
    let stash = GraphStep(from: 1, to: 0, color: .stash, stroke: .stash)
    let line = GraphStep(from: 0, to: 0, color: .head, stroke: .solid)
    let rows = [
        GraphRow(node: GraphNode(column: 1, kind: .stash, color: .stash, isGhost: false),
                 stepsAbove: [.uncommitted], stepsBelow: [.uncommitted, stash], width: 2),
        GraphRow(node: GraphNode(column: 0, kind: .commit, color: .head, isGhost: false),
                 stepsAbove: [.uncommitted, stash], stepsBelow: [line], width: 2),
        GraphRow(node: GraphNode(column: 0, kind: .commit, color: .head, isGhost: false),
                 stepsAbove: [line], stepsBelow: [], width: 2),
    ]
    HStack(alignment: .top, spacing: 24) {
        ForEach([DensityMetrics.regular, .compact], id: \.rowList) { density in
            let style = GraphStyle(metrics: density.graph)
            VStack(spacing: HistoryTableLayout.rowSpacing) {
                ZStack(alignment: .leading) {
                    UncommittedConnectorView(step: .uncommitted, maxLanes: 2, style: style,
                                             rowSpacing: HistoryTableLayout.rowSpacing)
                    RoundedRectangle(cornerRadius: GraphMetrics.squareMarkRadius)
                        .strokeBorder(theme.colors.mod, style: StrokeStyle(lineWidth: 1.5, dash: [2.5, 2]))
                        .frame(width: 9, height: 9)
                        .padding(.leading, density.graph.firstLaneX - 4.5)
                }
                .frame(height: density.rowList)
                ForEach(rows.indices, id: \.self) { index in
                    GraphColumnView(row: rows[index], maxLanes: 2, style: style,
                                    rowSpacing: HistoryTableLayout.rowSpacing, isHeadCommit: index == 1)
                        .frame(height: density.rowList)
                }
            }
        }
    }
    .padding()
    .background(Color.black)
}
