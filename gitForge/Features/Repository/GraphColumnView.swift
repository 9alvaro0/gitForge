import SwiftUI

struct GraphColumnView: View {
    let row: GraphRowLayout
    let maxLanes: Int
    var laneWidth: CGFloat = 18
    var dotRadius: CGFloat = 4.5

    var body: some View {
        Canvas { context, size in
            let center = size.height / 2
            let bottom = size.height
            let baseLineWidth: CGFloat = 1.8

            // Top-half lane segments (one per active lane that's not the commit lane,
            // because the commit lane is drawn explicitly below — full-height — for emphasis).
            for occ in row.lanesAtTop where occ.lane != row.commitLane {
                drawSegment(
                    context: context,
                    from: CGPoint(x: laneCenter(occ.lane), y: 0),
                    to: CGPoint(x: laneCenter(occ.lane), y: center),
                    color: Self.color(for: occ.branchId),
                    lineWidth: baseLineWidth
                )
            }

            // Bottom-half lane segments
            for occ in row.lanesAtBottom where occ.lane != row.commitLane {
                drawSegment(
                    context: context,
                    from: CGPoint(x: laneCenter(occ.lane), y: center),
                    to: CGPoint(x: laneCenter(occ.lane), y: bottom),
                    color: Self.color(for: occ.branchId),
                    lineWidth: baseLineWidth
                )
            }

            // The commit's own lane gets drawn full-height so the dot sits on a continuous spine
            let commitX = laneCenter(row.commitLane)
            drawSegment(
                context: context,
                from: CGPoint(x: commitX, y: 0),
                to: CGPoint(x: commitX, y: bottom),
                color: Self.color(for: row.commitBranchId),
                lineWidth: baseLineWidth + 0.4
            )

            // Merge-in curves: from the merging lane (top) into the commit lane (center).
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

            // Dot: filled disc on the commit lane, hollow centre for merges.
            let dotColor = Self.color(for: row.commitBranchId)
            let dotRect = CGRect(
                x: commitX - dotRadius,
                y: center - dotRadius,
                width: dotRadius * 2,
                height: dotRadius * 2
            )
            context.fill(Path(ellipseIn: dotRect), with: .color(dotColor))
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
        Color(red: 0.30, green: 0.65, blue: 0.95),  // blue
        Color(red: 0.97, green: 0.50, blue: 0.30),  // orange
        Color(red: 0.40, green: 0.78, blue: 0.50),  // green
        Color(red: 0.85, green: 0.45, blue: 0.85),  // pink
        Color(red: 0.95, green: 0.78, blue: 0.30),  // amber
        Color(red: 0.55, green: 0.50, blue: 0.95),  // indigo
        Color(red: 0.30, green: 0.80, blue: 0.80),  // teal
        Color(red: 0.92, green: 0.42, blue: 0.55),  // rose
        Color(red: 0.55, green: 0.78, blue: 0.40),  // lime
        Color(red: 0.78, green: 0.55, blue: 0.30),  // brown
        Color(red: 0.40, green: 0.55, blue: 0.85),  // cobalt
        Color(red: 0.85, green: 0.65, blue: 0.85),  // mauve
    ]
}

#Preview {
    let sample: [GraphRowLayout] = [
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
            lanesAtBottom: [LaneOccupation(lane: 0, branchId: 0), LaneOccupation(lane: 1, branchId: 2)],
            mergesIn: [],
            mergesOut: [LaneOccupation(lane: 1, branchId: 2)],
            totalLanes: 2,
            isMerge: false
        ),
        GraphRowLayout(
            commitLane: 0,
            commitBranchId: 0,
            lanesAtTop: [LaneOccupation(lane: 0, branchId: 0)],
            lanesAtBottom: [LaneOccupation(lane: 0, branchId: 0)],
            mergesIn: [],
            mergesOut: [],
            totalLanes: 1,
            isMerge: false
        ),
    ]
    return VStack(spacing: 0) {
        ForEach(0..<sample.count, id: \.self) { idx in
            GraphColumnView(row: sample[idx], maxLanes: 3)
                .frame(height: 56)
        }
    }
    .padding()
    .frame(width: 200)
}
