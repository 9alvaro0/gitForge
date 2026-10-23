import SwiftUI

/// The start of the connector under the Uncommitted changes row's square (§5.5): `step`'s
/// leaving half, painted by `GraphRowPainter` as a graph row would, over the same canvas
/// (one row pitch plus the bleed, centred on the row), with the square's area left clear so
/// its inside shows the row's background. The square itself stays the row's.
///
/// Only whole dots show under the square. The half's dots sit every `q` (half the dash
/// period of the canvas's own geometry) from `q/2` below the row's centre; drawn are those
/// whose centre is at least half the square's side plus a quarter of the stroke below the
/// centre, so none peeks out past the square's bottom edge as a nub. The view clears a rect
/// as wide as the square, from its top down to `max(squareSide/2, k0 · q)` below the centre,
/// `k0` being the first dot drawn: the middle of the gap before it, and never above the
/// square's bottom edge. At the table's pitches that keeps the regular density's dot at
/// 5.4375 pt (it touches the square by 0.06 pt, under a pixel) and hides the compact one's
/// at 4.3125 pt, whose first dot drawn is then the one at 7.1875 pt.
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
            let center = size.height / 2
            let clearBottom = Self.clearedDepth(squareSide: squareSide, edgeWidth: style.metrics.edgeWidth,
                                                dotSpacing: GraphRowGeometry(style: style, size: size,
                                                                             rowSpacing: rowSpacing).dashPeriod / 2)
            let cleared = CGRect(x: style.laneCenter(0) - squareSide / 2, y: center - squareSide / 2,
                                 width: squareSide, height: squareSide / 2 + clearBottom)
            context.clip(to: Path(cleared), options: .inverse)
            GraphRowPainter(style: style, size: size, rowSpacing: rowSpacing).drawSteps(of: row, in: &context)
        }
        // Framed like `GraphColumnView`: the layout keeps the row's height,
        // the canvas overhangs half the gap and the bleed on each side.
        .padding(.vertical, -(rowSpacing / 2 + GraphRowGeometry.bleed(for: style.metrics)))
        .frame(width: style.gutterWidth(lanes: maxLanes), alignment: .leading)
    }

    /// How far below the row's centre the cleared rect reaches, for dots `dotSpacing` (`q`)
    /// apart from `q/2` below it: `max(squareSide/2, k0 · q)`, where `k0` is the smallest
    /// `k` with `q/2 + k · q ≥ squareSide/2 + edgeWidth/4`, the first dot drawn.
    nonisolated static func clearedDepth(squareSide: CGFloat, edgeWidth: CGFloat, dotSpacing q: CGFloat) -> CGFloat {
        guard q > 0 else { return squareSide / 2 }
        let firstDrawn = max(0, ((squareSide / 2 + edgeWidth / 4 - q / 2) / q).rounded(.up))
        return max(squareSide / 2, firstDrawn * q)
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
