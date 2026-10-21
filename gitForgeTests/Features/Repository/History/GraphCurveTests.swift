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
}
