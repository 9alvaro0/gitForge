import CoreGraphics
import Foundation
import Testing
@testable import gitForge

@Suite("Graph — row geometry")
struct GraphRowGeometryTests {

    /// Regular metrics: lane `n` is centred at `14 + 14 n`.
    private static let style = GraphStyle(metrics: .regular)
    /// A 28 pt row plus the 1 pt gap to the next: the canvas one row draws in.
    private static let size = CGSize(width: 80, height: 28 + 1)

    private static func step(_ from: Int, _ to: Int, _ stroke: GraphStroke = .solid) -> GraphStep {
        GraphStep(from: from, to: to, color: .pool(0), stroke: stroke)
    }

    private static func row(above: [GraphStep] = [], below: [GraphStep] = []) -> GraphRow {
        GraphRow(node: GraphNode(column: 0, kind: .commit, color: .head, isGhost: false),
                 stepsAbove: above, stepsBelow: below, width: 3)
    }

    private static func segments(_ row: GraphRow, size: CGSize = size) -> [(GraphSegment, GraphStep)] {
        var all: [(GraphSegment, GraphStep)] = []
        GraphRowGeometry(style: style, size: size).forEachSegment(of: row) { all.append(($0, $1)) }
        return all
    }

    private static func curve(_ bezier: GraphCurve.Bezier) -> GraphSegment {
        .curve(start: bezier.start, control1: bezier.control1, control2: bezier.control2, end: bezier.end)
    }

    @Test("A straight step above runs from the top edge to the centre; below, from the centre to the bottom edge")
    func straightHalves() {
        let segments = Self.segments(Self.row(above: [Self.step(0, 0)], below: [Self.step(0, 0), Self.step(1, 1)]))
        #expect(segments.map(\.0) == [
            .line(from: CGPoint(x: 14, y: 0), to: CGPoint(x: 14, y: 14.5)),
            .line(from: CGPoint(x: 14, y: 14.5), to: CGPoint(x: 14, y: 29)),
            .line(from: CGPoint(x: 28, y: 14.5), to: CGPoint(x: 28, y: 29)),
        ])
    }

    @Test("A step above draws the arriving half of its S; a step below the leaving half, over the full pitch")
    func curveHalves() {
        let segments = Self.segments(Self.row(above: [Self.step(1, 0)], below: [Self.step(0, 2)]))
        #expect(segments.map(\.0) == [
            Self.curve(GraphCurve.arriving(fromX: 28, toX: 14, center: 14.5, height: 29)),
            Self.curve(GraphCurve.leaving(fromX: 14, toX: 42, center: 14.5, height: 29)),
        ])
    }

    @Test("Curves come first, then the straight halves, each with its own step")
    func drawingOrder() {
        let above = [Self.step(0, 0), Self.step(2, 1, .stash)]
        let below = [Self.step(0, 0), Self.step(1, 2)]
        let steps = Self.segments(Self.row(above: above, below: below)).map(\.1)
        #expect(steps == [above[1], below[1], above[0], below[0]])
    }

    @Test("Every half stays inside the canvas", arguments: [CGSize(width: 80, height: 29), CGSize(width: 80, height: 24)])
    func insideTheCanvas(size: CGSize) {
        let row = Self.row(above: [Self.step(0, 0), Self.step(2, 0), Self.step(0, 3)],
                           below: [Self.step(0, 0), Self.step(0, 1), Self.step(3, 2)])
        for (segment, _) in Self.segments(row, size: size) {
            for point in segment.points {
                #expect(point.y >= 0 && point.y <= size.height, "\(segment)")
            }
        }
    }

    @Test("Adjacent rows meet in the middle of the gap with the same point and the same tangent")
    func halvesMeet() {
        // Rows one pitch apart: the lower canvas starts where the upper one ends.
        let pitch = Self.size.height
        for (from, to) in [(0, 2), (3, 1)] {
            let step = Self.step(from, to)
            let upper = Self.segments(Self.row(below: [step]))[0].0
            let lower = Self.segments(Self.row(above: [step]))[0].0
            guard case let .curve(_, _, upperControl, upperEnd) = upper,
                  case let .curve(lowerStart, lowerControl, _, _) = lower else {
                Issue.record("\(from)>\(to) should draw two curve halves")
                continue
            }
            #expect(upperEnd == CGPoint(x: lowerStart.x, y: lowerStart.y + pitch))
            // The same tangent on both sides: one S split in two, no kink.
            #expect(upperEnd.x - upperControl.x == lowerControl.x - lowerStart.x)
            #expect(upperEnd.y - upperControl.y == lowerControl.y - lowerStart.y)
        }
        // A straight step: two verticals at the same x, meeting at the edge.
        let upper = Self.segments(Self.row(below: [Self.step(1, 1)]))[0].0.points
        let lower = Self.segments(Self.row(above: [Self.step(1, 1)]))[0].0.points
        #expect(upper.last == CGPoint(x: lower[0].x, y: lower[0].y + pitch))
    }

    @Test("In the gitflow graph every half a row leaves meets the half the next row arrives with")
    func gitflowJoins() {
        let refs = GraphFixture.gitflowRefs(head: "feature/cart")
        let rows = CommitGraphEngine.layout(GraphInput(commits: GraphFixture.gitflow, headSha: "cartPayment",
                                                       refs: refs, paletteSize: 4)).rows
        let pitch = Self.size.height
        for boundary in 0..<(rows.count - 1) {
            let leaving = Self.segments(Self.row(below: rows[boundary].stepsBelow))
            let arriving = Self.segments(Self.row(above: rows[boundary + 1].stepsAbove))
            #expect(leaving.count == arriving.count)
            let ends = Set(leaving.map { "\($0.1)|\($0.0.points.last!.x)|\($0.0.points.last!.y)" })
            let starts = Set(arriving.map { "\($0.1)|\($0.0.points[0].x)|\($0.0.points[0].y + pitch)" })
            #expect(ends == starts, "boundary \(boundary)")
        }
    }
}

private extension GraphSegment {
    /// Start first, end last.
    var points: [CGPoint] {
        switch self {
        case let .line(from, to): [from, to]
        case let .curve(start, control1, control2, end): [start, control1, control2, end]
        }
    }
}
