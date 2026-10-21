import SwiftUI

/// One half of a step, as a row draws it.
nonisolated enum GraphSegment: Equatable, Sendable {
    /// A half of a step that stays in its column.
    case line(from: CGPoint, to: CGPoint)
    /// A half of the S of a step that changes column (`GraphCurve`).
    case curve(start: CGPoint, control1: CGPoint, control2: CGPoint, end: CGPoint)

    var path: Path {
        var path = Path()
        switch self {
        case let .line(from, to):
            path.move(to: from)
            path.addLine(to: to)
        case let .curve(start, control1, control2, end):
            path.move(to: start)
            path.addCurve(to: end, control1: control1, control2: control2)
        }
        return path
    }
}

/// Where a row draws its halves of the steps that cross it (§5.1), as plain
/// geometry.
///
/// Rows sit one pitch apart: the row height plus the gap the table leaves
/// between rows. The canvas is one pitch tall and centred on its row, so its
/// centre is the row's centre and its edges sit in the middle of the gaps.
/// A step runs from one row centre to the next, one pitch below: the row
/// draws the arriving half of each `stepsAbove` (top edge to centre) and the
/// leaving half of each `stepsBelow` (centre to bottom edge), and the halves
/// of adjacent rows meet in the middle of the gap, at the same point and with
/// the same tangent.
nonisolated struct GraphRowGeometry {
    let style: GraphStyle
    /// The canvas: the gutter's width, one row pitch tall.
    let size: CGSize

    var center: CGFloat { size.height / 2 }

    /// Calls `body` with each half and its step, in drawing order: every
    /// curve first, then the straight halves, so a line passing through stays
    /// on top of the curves that cross it (§5.2). Allocates nothing.
    func forEachSegment(of row: GraphRow, _ body: (GraphSegment, GraphStep) -> Void) {
        for step in row.stepsAbove where step.from != step.to {
            body(curve(GraphCurve.arriving(fromX: style.laneCenter(step.from), toX: style.laneCenter(step.to),
                                           center: center, height: size.height)), step)
        }
        for step in row.stepsBelow where step.from != step.to {
            body(curve(GraphCurve.leaving(fromX: style.laneCenter(step.from), toX: style.laneCenter(step.to),
                                          center: center, height: size.height)), step)
        }
        for step in row.stepsAbove where step.from == step.to {
            let x = style.laneCenter(step.to)
            body(.line(from: CGPoint(x: x, y: 0), to: CGPoint(x: x, y: center)), step)
        }
        for step in row.stepsBelow where step.from == step.to {
            let x = style.laneCenter(step.from)
            body(.line(from: CGPoint(x: x, y: center), to: CGPoint(x: x, y: size.height)), step)
        }
    }

    private func curve(_ bezier: GraphCurve.Bezier) -> GraphSegment {
        .curve(start: bezier.start, control1: bezier.control1, control2: bezier.control2, end: bezier.end)
    }
}
