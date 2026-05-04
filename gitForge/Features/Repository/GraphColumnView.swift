import SwiftUI

struct GraphColumnView: View {
    let row: GraphRowLayout
    let maxLanes: Int
    var laneWidth: CGFloat = 16
    var dotRadius: CGFloat = 4

    var body: some View {
        Canvas { context, size in
            let center = size.height / 2
            let bottom = size.height
            let lineWidth: CGFloat = 1.6

            for lane in row.activeLanesAtTop where lane != row.commitLane || row.mergesIn.isEmpty == false {
                drawSegment(
                    in: context,
                    from: CGPoint(x: laneCenter(lane), y: 0),
                    to: CGPoint(x: laneCenter(lane), y: center),
                    color: Self.color(for: lane),
                    lineWidth: lineWidth
                )
            }

            for lane in row.activeLanesAtBottom where lane != row.commitLane || !row.mergesOut.isEmpty {
                drawSegment(
                    in: context,
                    from: CGPoint(x: laneCenter(lane), y: center),
                    to: CGPoint(x: laneCenter(lane), y: bottom),
                    color: Self.color(for: lane),
                    lineWidth: lineWidth
                )
            }

            // Always draw the commit lane through the row (above and below)
            drawSegment(
                in: context,
                from: CGPoint(x: laneCenter(row.commitLane), y: 0),
                to: CGPoint(x: laneCenter(row.commitLane), y: bottom),
                color: Self.color(for: row.commitLane),
                lineWidth: lineWidth
            )

            // mergesIn: curves from other lanes (top) into the commit lane (center)
            let commitX = laneCenter(row.commitLane)
            for lane in row.mergesIn {
                var path = Path()
                let startX = laneCenter(lane)
                path.move(to: CGPoint(x: startX, y: 0))
                path.addCurve(
                    to: CGPoint(x: commitX, y: center),
                    control1: CGPoint(x: startX, y: center * 0.7),
                    control2: CGPoint(x: commitX, y: center * 0.7)
                )
                context.stroke(path, with: .color(Self.color(for: lane)), lineWidth: lineWidth)
            }

            // mergesOut: curves from commit lane (center) to other lanes (bottom)
            for lane in row.mergesOut {
                var path = Path()
                let endX = laneCenter(lane)
                path.move(to: CGPoint(x: commitX, y: center))
                path.addCurve(
                    to: CGPoint(x: endX, y: bottom),
                    control1: CGPoint(x: commitX, y: center + (bottom - center) * 0.3),
                    control2: CGPoint(x: endX, y: center + (bottom - center) * 0.3)
                )
                context.stroke(path, with: .color(Self.color(for: lane)), lineWidth: lineWidth)
            }

            // Dot
            let dotColor = Self.color(for: row.commitLane)
            let dotRect = CGRect(
                x: commitX - dotRadius,
                y: center - dotRadius,
                width: dotRadius * 2,
                height: dotRadius * 2
            )
            context.fill(Path(ellipseIn: dotRect), with: .color(dotColor))
            if row.isMerge {
                let inner = dotRect.insetBy(dx: 1.6, dy: 1.6)
                context.fill(Path(ellipseIn: inner), with: .color(.white))
            }
        }
        .frame(width: CGFloat(maxLanes) * laneWidth, alignment: .leading)
    }

    private func laneCenter(_ lane: Int) -> CGFloat {
        CGFloat(lane) * laneWidth + laneWidth / 2
    }

    private func drawSegment(in context: GraphicsContext, from: CGPoint, to: CGPoint, color: Color, lineWidth: CGFloat) {
        var path = Path()
        path.move(to: from)
        path.addLine(to: to)
        context.stroke(path, with: .color(color), lineWidth: lineWidth)
    }

    static func color(for lane: Int) -> Color {
        palette[lane % palette.count]
    }

    private static let palette: [Color] = [
        .blue, .purple, .green, .orange, .pink, .teal, .yellow, .red, .indigo, .mint
    ]
}

#Preview {
    let sample = [
        GraphRowLayout(commitLane: 0, activeLanesAtTop: [0, 1], activeLanesAtBottom: [0, 1], mergesIn: [], mergesOut: [], totalLanes: 2, isMerge: false),
        GraphRowLayout(commitLane: 0, activeLanesAtTop: [0, 1], activeLanesAtBottom: [0], mergesIn: [1], mergesOut: [], totalLanes: 2, isMerge: true),
        GraphRowLayout(commitLane: 0, activeLanesAtTop: [0], activeLanesAtBottom: [0, 1], mergesIn: [], mergesOut: [1], totalLanes: 2, isMerge: false),
        GraphRowLayout(commitLane: 0, activeLanesAtTop: [0], activeLanesAtBottom: [0], mergesIn: [], mergesOut: [], totalLanes: 1, isMerge: false),
    ]
    return VStack(spacing: 0) {
        ForEach(0..<sample.count, id: \.self) { idx in
            GraphColumnView(row: sample[idx], maxLanes: 3)
                .frame(height: 56)
                .background(idx.isMultiple(of: 2) ? Color.gray.opacity(0.05) : .clear)
        }
    }
    .padding()
    .frame(width: 200)
}
