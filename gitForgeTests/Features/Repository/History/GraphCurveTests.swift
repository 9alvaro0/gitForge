import CoreGraphics
import Foundation
import Testing
@testable import gitForge

@Suite("GraphCurve")
struct GraphCurveTests {
    @Test("Both halves meet at the row boundary, halfway across")
    func halves() {
        let up = GraphCurve.leaving(fromX: 14, toX: 42, center: 14, height: 28)
        #expect(up.start == CGPoint(x: 14, y: 14) && up.control1 == CGPoint(x: 14, y: 21))
        #expect(up.control2 == CGPoint(x: 21, y: 24.5) && up.end == CGPoint(x: 28, y: 28))
        let down = GraphCurve.arriving(fromX: 14, toX: 42, center: 14, height: 28)
        #expect(down.start == CGPoint(x: 28, y: 0) && down.control1 == CGPoint(x: 35, y: 3.5))
        #expect(down.control2 == CGPoint(x: 42, y: 7) && down.end == CGPoint(x: 42, y: 14))
    }

    @Test("A piece of a curve traces the curve between its two parameters")
    func piece() {
        let s = GraphCurve.step(fromX: 14, toX: 56, top: 3, height: 29)
        let piece = GraphCurve.piece(of: s, from: 0.3, to: 0.8)
        for index in 0...10 {
            let u = CGFloat(index) / 10
            Self.expectClose(GraphCurve.point(on: piece, at: u), GraphCurve.point(on: s, at: 0.3 + 0.5 * u))
        }
        // The whole range is the curve itself, exactly.
        let whole = GraphCurve.piece(of: s, from: 0, to: 1)
        #expect(whole.start == s.start && whole.control1 == s.control1)
        #expect(whole.control2 == s.control2 && whole.end == s.end)
    }

    @Test("The parameter past the middle puts the S that far below (and above) its middle, whatever its columns",
          arguments: [CGFloat(0), 0.5, 0.875, 1, 3], [CGFloat(23), 29])
    func parameterPastMiddle(overlap: CGFloat, height: CGFloat) {
        let past = GraphCurve.parameter(pastMiddleBy: overlap, height: height)
        if overlap == 0 { #expect(past == 0) }
        for x1 in [CGFloat(14), 70] {
            let s = GraphCurve.step(fromX: 14, toX: x1, top: 0, height: height)
            #expect(abs(GraphCurve.point(on: s, at: 0.5 + past).y - (height / 2 + overlap)) < 1e-12)
            #expect(abs(GraphCurve.point(on: s, at: 0.5 - past).y - (height / 2 - overlap)) < 1e-12)
        }
    }

    @Test("With an overlap, each half runs that far past the middle of the gap along the same S")
    func overlappingHalves() {
        let past = GraphCurve.parameter(pastMiddleBy: 1, height: 28)
        let up = GraphCurve.leaving(fromX: 14, toX: 42, center: 14, height: 28, overlap: 1)
        let upperS = GraphCurve.step(fromX: 14, toX: 42, top: 14, height: 28)
        #expect(up.start == CGPoint(x: 14, y: 14))
        #expect(abs(up.end.y - 29) < 1e-12)
        let down = GraphCurve.arriving(fromX: 14, toX: 42, center: 14, height: 28, overlap: 1)
        let lowerS = GraphCurve.step(fromX: 14, toX: 42, top: -14, height: 28)
        #expect(abs(down.start.y - -1) < 1e-12)
        #expect(down.end == CGPoint(x: 42, y: 14))
        for index in 0...10 {
            let u = CGFloat(index) / 10
            Self.expectClose(GraphCurve.point(on: up, at: u), GraphCurve.point(on: upperS, at: u * (0.5 + past)))
            Self.expectClose(GraphCurve.point(on: down, at: u),
                             GraphCurve.point(on: lowerS, at: 0.5 - past + u * (0.5 + past)))
        }
    }

    private static func expectClose(_ a: CGPoint, _ b: CGPoint,
                                    sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(abs(a.x - b.x) < 1e-9 && abs(a.y - b.y) < 1e-9, "\(a) vs \(b)", sourceLocation: sourceLocation)
    }
}
