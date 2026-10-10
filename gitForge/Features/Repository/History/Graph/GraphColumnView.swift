import SwiftUI

/// Everything a graph row needs to paint itself in the v2 style (redesign
/// spec §4.5), resolved once per table render instead of once per row.
nonisolated struct GraphStyle: Equatable, Sendable {
    var metrics: GraphMetrics = .regular
    var accent: AccentSwatch = .violet
    /// `theme.colors.accent`, the HEAD lane colour.
    var accentColor: Color = .accentColor
    var dark: Bool = true
    /// Fill behind hollow nodes; matches the table background.
    var nodeFill: Color = .black
    /// Branch id whose lane is HEAD's, so it takes the accent.
    var headBranchId: Int?

    func laneColor(branchId: Int, priorityRank: Int?, isStash: Bool) -> Color {
        if isStash { return LaneColors.stash(dark: dark) }
        let assignment = LaneColors.assignment(
            branchId: branchId,
            priorityRank: priorityRank,
            isHead: branchId == headBranchId,
            accent: accent
        )
        return LaneColors.color(assignment, dark: dark, accent: accentColor)
    }

    func laneCenter(_ lane: Int) -> CGFloat {
        metrics.firstLaneX + CGFloat(lane) * metrics.laneWidth
    }

    /// Width the gutter needs for `lanes` lanes, with the same margin on both sides.
    func gutterWidth(lanes: Int) -> CGFloat {
        2 * metrics.firstLaneX + CGFloat(max(lanes, 1) - 1) * metrics.laneWidth
    }
}

struct GraphColumnView: View {
    let row: GraphRowLayout
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
            let center = size.height / 2
            let bottom = size.height
            let edge = style.metrics.edgeWidth

            let mergesInLanes = Set(row.mergesIn.map(\.lane))
            let lanesAtTopSet = Set(row.lanesAtTop.map(\.lane))
            // A merges-out lane only replaces its own vertical when the parent is brand new
            // (didn't exist in a lane above this row). Existing parent lanes keep their
            // continuation line; the merge curve draws ON TOP of it.
            let newMergesOutLanes = Set(row.mergesOut.map(\.lane)).subtracting(lanesAtTopSet)
            // A merge-in landing in the SAME column as the commit lane already paints
            // the row's top half in the merge-in style; skipping the commit spine
            // keeps a solid spine from over-painting a dashed stash tail.
            let commitInTop = lanesAtTopSet.contains(row.commitLane)
                && !mergesInLanes.contains(row.commitLane)
            let commitInBottom = row.lanesAtBottom.contains { $0.lane == row.commitLane }

            func color(for occ: LaneOccupation) -> Color {
                style.laneColor(branchId: occ.branchId, priorityRank: occ.priorityRank, isStash: occ.isStash)
            }
            // Stashes ride dashed lanes: "a saved working state, not a branch".
            func strokeStyle(stash: Bool) -> StrokeStyle {
                stash
                    ? StrokeStyle(lineWidth: edge, lineCap: .round, lineJoin: .round, dash: [3, 3])
                    : StrokeStyle(lineWidth: edge, lineCap: .round, lineJoin: .round)
            }
            // Orthogonal routing with a small rounded corner: lanes read as
            // "right angle in, right angle out", not as bezier S-curves.
            let cornerRadius: CGFloat = 4.0

            for occ in row.lanesAtTop where occ.lane != row.commitLane && !mergesInLanes.contains(occ.lane) {
                var path = Path()
                path.move(to: CGPoint(x: style.laneCenter(occ.lane), y: 0))
                path.addLine(to: CGPoint(x: style.laneCenter(occ.lane), y: center))
                context.stroke(path, with: .color(color(for: occ)), style: strokeStyle(stash: occ.isStash))
            }

            for occ in row.lanesAtBottom where occ.lane != row.commitLane && !newMergesOutLanes.contains(occ.lane) {
                var path = Path()
                path.move(to: CGPoint(x: style.laneCenter(occ.lane), y: center))
                path.addLine(to: CGPoint(x: style.laneCenter(occ.lane), y: bottom))
                context.stroke(path, with: .color(color(for: occ)), style: strokeStyle(stash: occ.isStash))
            }

            // Merge-in: vertical from the row top, a rounded right angle, then a
            // horizontal into the commit node. Degenerate same-column case is a
            // straight vertical (no hook).
            let commitX = style.laneCenter(row.commitLane)
            for occ in row.mergesIn {
                let startX = style.laneCenter(occ.lane)
                var path = Path()
                if abs(startX - commitX) < 0.5 {
                    path.move(to: CGPoint(x: startX, y: 0))
                    path.addLine(to: CGPoint(x: startX, y: center))
                } else {
                    let dir: CGFloat = startX > commitX ? -1 : 1
                    path.move(to: CGPoint(x: startX, y: 0))
                    path.addLine(to: CGPoint(x: startX, y: center - cornerRadius))
                    path.addQuadCurve(
                        to: CGPoint(x: startX + dir * cornerRadius, y: center),
                        control: CGPoint(x: startX, y: center)
                    )
                    path.addLine(to: CGPoint(x: commitX, y: center))
                }
                context.stroke(path, with: .color(color(for: occ)), style: strokeStyle(stash: occ.isStash))
            }

            // Merge-out: a brand-new lane leaves the node horizontally and turns
            // down; an existing lane just gets a horizontal connector.
            for occ in row.mergesOut {
                let endX = style.laneCenter(occ.lane)
                var path = Path()
                if newMergesOutLanes.contains(occ.lane) {
                    let dir: CGFloat = endX > commitX ? 1 : -1
                    path.move(to: CGPoint(x: commitX, y: center))
                    path.addLine(to: CGPoint(x: endX - dir * cornerRadius, y: center))
                    path.addQuadCurve(
                        to: CGPoint(x: endX, y: center + cornerRadius),
                        control: CGPoint(x: endX, y: center)
                    )
                    path.addLine(to: CGPoint(x: endX, y: bottom))
                } else {
                    path.move(to: CGPoint(x: commitX, y: center))
                    path.addLine(to: CGPoint(x: endX, y: center))
                }
                context.stroke(path, with: .color(color(for: occ)), style: strokeStyle(stash: occ.isStash))
            }

            // The commit's own spine: top half only if it came from above, bottom
            // half only if it continues; tips and roots get no phantom stub.
            let commitColor = style.laneColor(
                branchId: row.commitBranchId,
                priorityRank: row.commitPriorityRank,
                isStash: row.commitIsStash
            )
            if commitInTop {
                var path = Path()
                path.move(to: CGPoint(x: commitX, y: 0))
                path.addLine(to: CGPoint(x: commitX, y: center))
                context.stroke(path, with: .color(commitColor), style: strokeStyle(stash: row.commitIsStash))
            }
            if commitInBottom {
                var path = Path()
                path.move(to: CGPoint(x: commitX, y: center))
                path.addLine(to: CGPoint(x: commitX, y: bottom))
                context.stroke(path, with: .color(commitColor), style: strokeStyle(stash: row.commitIsStash))
            }

            // Node (spec §4.5). Selection gets a soft halo in the lane colour,
            // hover a thin ring.
            let m = style.metrics
            let nodeCenter = CGPoint(x: commitX, y: center)
            let outer: CGFloat = {
                switch node {
                case .head:  return m.headOuterRadius
                case .stash: return m.stashSize / 2
                default:     return m.nodeRadius
                }
            }()
            func circle(_ r: CGFloat) -> Path {
                Path(ellipseIn: CGRect(x: nodeCenter.x - r, y: nodeCenter.y - r, width: r * 2, height: r * 2))
            }
            if isSelected {
                context.fill(circle(outer + m.selectHaloOutset), with: .color(commitColor.opacity(m.selectHaloOpacity)))
            } else if isHovered {
                context.stroke(circle(outer + m.hoverRingOutset),
                               with: .color(commitColor.opacity(m.hoverRingOpacity)),
                               lineWidth: m.hoverRingWidth)
            }
            switch node {
            case .commit:
                context.fill(circle(m.nodeRadius), with: .color(commitColor))
            case .merge:
                let ring = circle(m.nodeRadius - edge / 2)
                context.fill(ring, with: .color(style.nodeFill))
                context.stroke(ring, with: .color(commitColor), lineWidth: edge)
            case .head:
                let ring = circle(m.headOuterRadius - 0.75)
                context.fill(ring, with: .color(style.nodeFill))
                context.stroke(ring, with: .color(commitColor), lineWidth: 1.5)
                context.fill(circle(m.headInnerRadius), with: .color(commitColor))
            case .stash:
                let side = m.stashSize
                let square = Path(
                    roundedRect: CGRect(x: nodeCenter.x - side / 2, y: nodeCenter.y - side / 2, width: side, height: side),
                    cornerRadius: 2
                )
                context.fill(square, with: .color(style.nodeFill))
                context.stroke(square, with: .color(commitColor),
                               style: StrokeStyle(lineWidth: 1.5, dash: [2.5, 2]))
            }
        }
        .frame(width: style.gutterWidth(lanes: maxLanes), alignment: .leading)
    }
}

#Preview {
    let sample: [GraphRowLayout] = [
        GraphRowLayout(
            commitLane: 0, commitBranchId: 0, lanesAtTop: [],
            lanesAtBottom: [LaneOccupation(lane: 0, branchId: 0), LaneOccupation(lane: 1, branchId: 1)],
            mergesIn: [], mergesOut: [LaneOccupation(lane: 1, branchId: 1)],
            totalLanes: 2, isMerge: false
        ),
        GraphRowLayout(
            commitLane: 0, commitBranchId: 0,
            lanesAtTop: [LaneOccupation(lane: 0, branchId: 0), LaneOccupation(lane: 1, branchId: 1)],
            lanesAtBottom: [LaneOccupation(lane: 0, branchId: 0), LaneOccupation(lane: 1, branchId: 1)],
            mergesIn: [], mergesOut: [], totalLanes: 2, isMerge: false
        ),
        GraphRowLayout(
            commitLane: 0, commitBranchId: 0,
            lanesAtTop: [LaneOccupation(lane: 0, branchId: 0), LaneOccupation(lane: 1, branchId: 1)],
            lanesAtBottom: [LaneOccupation(lane: 0, branchId: 0)],
            mergesIn: [LaneOccupation(lane: 1, branchId: 1)], mergesOut: [],
            totalLanes: 2, isMerge: true
        ),
    ]
    VStack(spacing: 0) {
        ForEach(0..<sample.count, id: \.self) { idx in
            GraphColumnView(row: sample[idx], maxLanes: 2, isHeadCommit: idx == 0, isSelected: idx == 1)
                .frame(height: 28)
        }
    }
    .padding()
    .background(Color.black)
}
