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
            let baseLineWidth: CGFloat = 2.4

            let mergesInLanes = Set(row.mergesIn.map(\.lane))
            let lanesAtTopSet = Set(row.lanesAtTop.map(\.lane))
            // A merges-out lane only replaces its own vertical when the parent is brand new
            // (didn't exist in a lane above this row). Existing parent lanes keep their
            // continuation line; the merge curve draws ON TOP of it.
            let newMergesOutLanes = Set(row.mergesOut.map(\.lane)).subtracting(lanesAtTopSet)
            let commitInTop = lanesAtTopSet.contains(row.commitLane)
            let commitInBottom = row.lanesAtBottom.contains { $0.lane == row.commitLane }

            // Vertical top→center segments. Skip:
            //   • the commit lane (drawn last so it renders on top of crossing curves)
            //   • merge-in lanes (replaced by an in-curve)
            for occ in row.lanesAtTop where occ.lane != row.commitLane && !mergesInLanes.contains(occ.lane) {
                drawSegment(
                    context: context,
                    from: CGPoint(x: laneCenter(occ.lane), y: 0),
                    to: CGPoint(x: laneCenter(occ.lane), y: center),
                    color: Self.color(for: occ.branchId),
                    lineWidth: baseLineWidth
                )
            }

            // Vertical center→bottom segments. Skip the commit lane and brand-new
            // merges-out lanes (those have just the curve carrying them in).
            for occ in row.lanesAtBottom where occ.lane != row.commitLane && !newMergesOutLanes.contains(occ.lane) {
                drawSegment(
                    context: context,
                    from: CGPoint(x: laneCenter(occ.lane), y: center),
                    to: CGPoint(x: laneCenter(occ.lane), y: bottom),
                    color: Self.color(for: occ.branchId),
                    lineWidth: baseLineWidth
                )
            }

            // Merge-in curves: from the merging lane (top) into the commit lane (center).
            let commitX = laneCenter(row.commitLane)
            for occ in row.mergesIn {
                let startX = laneCenter(occ.lane)
                var path = Path()
                path.move(to: CGPoint(x: startX, y: 0))
                path.addCurve(
                    to: CGPoint(x: commitX, y: center),
                    control1: CGPoint(x: startX, y: center * 0.55),
                    control2: CGPoint(x: commitX, y: center * 0.45)
                )
                context.stroke(path, with: .color(Self.color(for: occ.branchId)), lineWidth: baseLineWidth)
            }

            // Merge-out curves: from the commit lane (center) into the new parent lane (bottom).
            for occ in row.mergesOut {
                let endX = laneCenter(occ.lane)
                var path = Path()
                path.move(to: CGPoint(x: commitX, y: center))
                path.addCurve(
                    to: CGPoint(x: endX, y: bottom),
                    control1: CGPoint(x: commitX, y: center + (bottom - center) * 0.45),
                    control2: CGPoint(x: endX, y: center + (bottom - center) * 0.55)
                )
                context.stroke(path, with: .color(Self.color(for: occ.branchId)), lineWidth: baseLineWidth)
            }

            // Commit's own lane spine. Top half only if it came in from above; bottom half only
            // if it continues below. New tips and root commits no longer get a phantom stub.
            let commitColor = Self.color(for: row.commitBranchId)
            if commitInTop {
                drawSegment(
                    context: context,
                    from: CGPoint(x: commitX, y: 0),
                    to: CGPoint(x: commitX, y: center),
                    color: commitColor,
                    lineWidth: baseLineWidth + 0.6
                )
            }
            if commitInBottom {
                drawSegment(
                    context: context,
                    from: CGPoint(x: commitX, y: center),
                    to: CGPoint(x: commitX, y: bottom),
                    color: commitColor,
                    lineWidth: baseLineWidth + 0.6
                )
            }

            // Dot: filled disc on the commit lane, hollow centre for merges.
            let dotRect = CGRect(
                x: commitX - dotRadius,
                y: center - dotRadius,
                width: dotRadius * 2,
                height: dotRadius * 2
            )
            context.fill(Path(ellipseIn: dotRect), with: .color(commitColor))
            if row.isMerge {
                context.fill(
                    Path(ellipseIn: dotRect.insetBy(dx: 1.6, dy: 1.6)),
                    with: .color(.white)
                )
            }
        }
        .frame(width: CGFloat(maxLanes) * laneWidth, alignment: .leading)
    }

    private func laneCenter(_ lane: Int) -> CGFloat {
        CGFloat(lane) * laneWidth + laneWidth / 2
    }

    private func drawSegment(context: GraphicsContext, from: CGPoint, to: CGPoint, color: Color, lineWidth: CGFloat) {
        var path = Path()
        path.move(to: from)
        path.addLine(to: to)
        context.stroke(path, with: .color(color), lineWidth: lineWidth)
    }

    static func color(for branchId: Int) -> Color {
        palette[branchId % palette.count]
    }

    /// 12 distinct hues so neighboring branches contrast well even in dense histories.
    private static let palette: [Color] = [
        Color(red: 0.30, green: 0.65, blue: 0.95),
        Color(red: 0.97, green: 0.50, blue: 0.30),
        Color(red: 0.40, green: 0.78, blue: 0.50),
        Color(red: 0.85, green: 0.45, blue: 0.85),
        Color(red: 0.95, green: 0.78, blue: 0.30),
        Color(red: 0.55, green: 0.50, blue: 0.95),
        Color(red: 0.30, green: 0.80, blue: 0.80),
        Color(red: 0.92, green: 0.42, blue: 0.55),
        Color(red: 0.55, green: 0.78, blue: 0.40),
        Color(red: 0.78, green: 0.55, blue: 0.30),
        Color(red: 0.40, green: 0.55, blue: 0.85),
        Color(red: 0.85, green: 0.65, blue: 0.85),
    ]
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
    return VStack(spacing: 0) {
        ForEach(0..<sample.count, id: \.self) { idx in
            GraphColumnView(row: sample[idx], maxLanes: 2)
                .frame(height: 60)
        }
    }
    .padding()
    .frame(width: 200)
}
