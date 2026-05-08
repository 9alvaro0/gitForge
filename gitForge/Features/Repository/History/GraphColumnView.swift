import SwiftUI

struct GraphColumnView: View {
    let row: GraphRowLayout
    let maxLanes: Int
    var laneWidth: CGFloat = 14
    var dotRadius: CGFloat = 4.5

    var body: some View {
        Canvas { context, size in
            let center = size.height / 2
            let bottom = size.height
            let baseLineWidth: CGFloat = 1.8
            // Pinned trunks (main/develop/release/trunk) ride a fatter spine so
            // the eye locks onto them in dense histories.
            let priorityLineWidth: CGFloat = 3.0

            let mergesInLanes = Set(row.mergesIn.map(\.lane))
            let lanesAtTopSet = Set(row.lanesAtTop.map(\.lane))
            // A merges-out lane only replaces its own vertical when the parent is brand new
            // (didn't exist in a lane above this row). Existing parent lanes keep their
            // continuation line; the merge curve draws ON TOP of it.
            let newMergesOutLanes = Set(row.mergesOut.map(\.lane)).subtracting(lanesAtTopSet)
            let commitInTop = lanesAtTopSet.contains(row.commitLane)
            let commitInBottom = row.lanesAtBottom.contains { $0.lane == row.commitLane }

            func width(for occ: LaneOccupation) -> CGFloat {
                occ.priorityRank == nil ? baseLineWidth : priorityLineWidth
            }
            func color(for occ: LaneOccupation) -> Color {
                Self.color(branchId: occ.branchId, priorityRank: occ.priorityRank)
            }
            // Stashes ride dashed lanes — the visual cue that says "this isn't a real
            // branch, it's a saved working state hanging off some commit".
            // Orthogonal joints look crisper with butt caps and round joins (the
            // round join smooths the L-corner without adding caps mid-segment that
            // would show as bumps where line meets quad-curve).
            func style(for occ: LaneOccupation) -> StrokeStyle {
                if occ.isStash {
                    return StrokeStyle(lineWidth: width(for: occ), lineCap: .butt, lineJoin: .round, dash: [3, 2.5])
                }
                return StrokeStyle(lineWidth: width(for: occ), lineCap: .butt, lineJoin: .round)
            }
            // L-corner radius for orthogonal routing. Kept small so lanes read as
            // "right-angle in, right-angle out" — too round and they look bezier
            // again, defeating the purpose.
            let cornerRadius: CGFloat = 4.0

            // Vertical top→center segments. Skip:
            //   • the commit lane (drawn last so it renders on top of crossing curves)
            //   • merge-in lanes (replaced by an in-curve)
            for occ in row.lanesAtTop where occ.lane != row.commitLane && !mergesInLanes.contains(occ.lane) {
                var path = Path()
                path.move(to: CGPoint(x: laneCenter(occ.lane), y: 0))
                path.addLine(to: CGPoint(x: laneCenter(occ.lane), y: center))
                context.stroke(path, with: .color(color(for: occ)), style: style(for: occ))
            }

            // Vertical center→bottom segments. Skip the commit lane and brand-new
            // merges-out lanes (those have just the curve carrying them in).
            for occ in row.lanesAtBottom where occ.lane != row.commitLane && !newMergesOutLanes.contains(occ.lane) {
                var path = Path()
                path.move(to: CGPoint(x: laneCenter(occ.lane), y: center))
                path.addLine(to: CGPoint(x: laneCenter(occ.lane), y: bottom))
                context.stroke(path, with: .color(color(for: occ)), style: style(for: occ))
            }

            // Merge-in: orthogonal L-route from the merging lane (top) into the
            // commit lane at center. Goes vertical down from row top, then turns
            // 90° into a horizontal that lands on the commit dot. The corner is
            // a tiny quad-curve so the join reads as "rounded right-angle" rather
            // than a bezier S.
            //
            // Degenerate case: the closing lane and the new commit lane share
            // the same column (happens when a stash lane converges to a fresh
            // trunk lane the engine just opened in the same column). Then the
            // L collapses to a straight vertical — no horizontal segment, no
            // corner. Drawing the curve would produce a tiny right-side hook.
            let commitX = laneCenter(row.commitLane)
            for occ in row.mergesIn {
                let startX = laneCenter(occ.lane)
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
                context.stroke(path, with: .color(color(for: occ)), style: style(for: occ))
            }

            // Merge-out: two cases.
            //   • Brand-new lane (born here): horizontal from commit dot → 90°
            //     turn down → vertical to row bottom, where the next row picks
            //     it up as a normal lane vertical.
            //   • Preexisting lane: the lane's top→center→bottom verticals are
            //     already drawn; we just connect the commit dot to that lane
            //     with a horizontal at center. No corner needed.
            for occ in row.mergesOut {
                let endX = laneCenter(occ.lane)
                var path = Path()
                if newMergesOutLanes.contains(occ.lane) {
                    let dir: CGFloat = endX > commitX ? 1 : -1  // away from commit
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
                context.stroke(path, with: .color(color(for: occ)), style: style(for: occ))
            }

            // Commit's own lane spine. Top half only if it came in from above; bottom half only
            // if it continues below. New tips and root commits no longer get a phantom stub.
            let isPriorityCommit = row.commitPriorityRank != nil
            let commitColor = Self.color(branchId: row.commitBranchId, priorityRank: row.commitPriorityRank)
            let commitSpineWidth = isPriorityCommit ? priorityLineWidth + 0.4 : baseLineWidth + 0.6
            let commitSpineStyle: StrokeStyle = row.commitIsStash
                ? StrokeStyle(lineWidth: commitSpineWidth, lineCap: .butt, lineJoin: .round, dash: [3, 2.5])
                : StrokeStyle(lineWidth: commitSpineWidth, lineCap: .butt, lineJoin: .round)
            if commitInTop {
                var path = Path()
                path.move(to: CGPoint(x: commitX, y: 0))
                path.addLine(to: CGPoint(x: commitX, y: center))
                context.stroke(path, with: .color(commitColor), style: commitSpineStyle)
            }
            if commitInBottom {
                var path = Path()
                path.move(to: CGPoint(x: commitX, y: center))
                path.addLine(to: CGPoint(x: commitX, y: bottom))
                context.stroke(path, with: .color(commitColor), style: commitSpineStyle)
            }

            // Dot rendering. Three variants:
            //   • Stash      → small filled diamond + dashed ring halo. Reads as
            //                  "frozen working state, off-tree".
            //   • Priority   → larger filled disc with a soft halo (trunk anchor).
            //   • Merge      → filled disc with a hollow white center.
            //   • Plain      → filled disc.
            if row.commitIsStash {
                let r = dotRadius - 0.8
                var diamond = Path()
                diamond.move(to: CGPoint(x: commitX, y: center - r))
                diamond.addLine(to: CGPoint(x: commitX + r, y: center))
                diamond.addLine(to: CGPoint(x: commitX, y: center + r))
                diamond.addLine(to: CGPoint(x: commitX - r, y: center))
                diamond.closeSubpath()
                context.fill(diamond, with: .color(commitColor))
                // Dashed halo so the stash glyph sits inside its own visual capsule.
                let haloRadius = dotRadius + 1.6
                let halo = CGRect(
                    x: commitX - haloRadius,
                    y: center - haloRadius,
                    width: haloRadius * 2,
                    height: haloRadius * 2
                )
                context.stroke(
                    Path(ellipseIn: halo),
                    with: .color(commitColor.opacity(0.7)),
                    style: StrokeStyle(lineWidth: DesignTokens.Stroke.regular, dash: [1.5, 1.5])
                )
            } else {
                let radius = isPriorityCommit ? dotRadius + 1.0 : dotRadius
                let dotRect = CGRect(
                    x: commitX - radius,
                    y: center - radius,
                    width: radius * 2,
                    height: radius * 2
                )
                if isPriorityCommit {
                    let halo = dotRect.insetBy(dx: -2.0, dy: -2.0)
                    context.fill(Path(ellipseIn: halo), with: .color(commitColor.opacity(DesignTokens.Opacity.muted)))
                }
                context.fill(Path(ellipseIn: dotRect), with: .color(commitColor))
                if row.isMerge {
                    context.fill(
                        Path(ellipseIn: dotRect.insetBy(dx: 1.6, dy: 1.6)),
                        with: .color(.white)
                    )
                }
            }
        }
        .frame(width: CGFloat(maxLanes) * laneWidth, alignment: .leading)
    }

    private func laneCenter(_ lane: Int) -> CGFloat {
        CGFloat(lane) * laneWidth + laneWidth / 2
    }

    static func color(branchId: Int, priorityRank: Int? = nil) -> Color {
        // Pinned trunks paint with fixed, saturated hues so the eye instantly
        // anchors on main / develop / trunk wherever they appear in the graph.
        // release/* (rank 2) keeps the hashed palette so concurrent siblings
        // (release/1.0.13 vs release/1.0.14) remain visually distinguishable.
        switch priorityRank {
        case 0: return GraphPalette.main
        case 1: return GraphPalette.develop
        case 3: return GraphPalette.trunk
        default: return GraphPalette.lanes[branchId % GraphPalette.lanes.count]
        }
    }
}

#Preview {
    let sample: [GraphRowLayout] = [
        GraphRowLayout(
            commitLane: 0,
            commitBranchId: 0,
            lanesAtTop: [],
            lanesAtBottom: [LaneOccupation(lane: 0, branchId: 0), LaneOccupation(lane: 1, branchId: 1)],
            mergesIn: [],
            mergesOut: [LaneOccupation(lane: 1, branchId: 1)],
            totalLanes: 2,
            isMerge: false
        ),
        GraphRowLayout(
            commitLane: 0,
            commitBranchId: 0,
            lanesAtTop: [LaneOccupation(lane: 0, branchId: 0), LaneOccupation(lane: 1, branchId: 1)],
            lanesAtBottom: [LaneOccupation(lane: 0, branchId: 0), LaneOccupation(lane: 1, branchId: 1)],
            mergesIn: [],
            mergesOut: [],
            totalLanes: 2,
            isMerge: false
        ),
        GraphRowLayout(
            commitLane: 0,
            commitBranchId: 0,
            lanesAtTop: [LaneOccupation(lane: 0, branchId: 0), LaneOccupation(lane: 1, branchId: 1)],
            lanesAtBottom: [LaneOccupation(lane: 0, branchId: 0)],
            mergesIn: [LaneOccupation(lane: 1, branchId: 1)],
            mergesOut: [],
            totalLanes: 2,
            isMerge: true
        ),
        GraphRowLayout(
            commitLane: 0,
            commitBranchId: 0,
            lanesAtTop: [LaneOccupation(lane: 0, branchId: 0)],
            lanesAtBottom: [],
            mergesIn: [],
            mergesOut: [],
            totalLanes: 1,
            isMerge: false
        ),
    ]
    VStack(spacing: DesignTokens.Spacing.none) {
        ForEach(0..<sample.count, id: \.self) { idx in
            GraphColumnView(row: sample[idx], maxLanes: 2)
                .frame(height: 60)
        }
    }
    .padding()
    .frame(width: 200)
}
