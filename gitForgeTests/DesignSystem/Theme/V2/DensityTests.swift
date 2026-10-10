import Foundation
import Testing
@testable import gitForge

/// `Density` is main-actor isolated (target default isolation), unlike the
/// `nonisolated` v2 types, so this suite runs on the main actor.
@Suite("Density v2")
@MainActor
struct DensityTests {

    @Test("Only compact and regular remain")
    func cases() {
        #expect(Density.allCases == [.compact, .regular])
    }

    @Test("Stored values resolve; comfy, empty and unknown fall back to regular",
          arguments: [("compact", Density.compact), ("regular", .regular), ("comfy", .regular), ("", .regular), ("huge", .regular)])
    func resolve(raw: String, expected: Density) {
        #expect(Density.resolve(raw) == expected)
    }

    @Test("Nothing stored resolves to regular")
    func resolveNil() {
        #expect(Density.resolve(nil) == .regular)
    }

    @Test("Metrics match the design sheet")
    func metrics() {
        #expect(Density.regular.metrics.rowList == 28)
        #expect(Density.compact.metrics.rowList == 22)
        #expect(Density.compact.metrics.diffLine == 17)
        #expect(Density.compact.metrics.buttonRegular == 24)
        #expect(Density.regular.metrics.inspectorWidth == 480)
        #expect(Density.regular.metrics.graph.laneWidth == 14)
        #expect(Density.compact.metrics.graph.nodeRadius == 3.75)
        #expect(Density.compact.metrics.graph.chipHeight == 16)
    }

    @Test("v1 values are untouched until the screens migrate")
    func legacyUnchanged() {
        #expect(Density.regular.rowHeight == 30)
        #expect(Density.compact.rowHeight == 26)
        #expect(Density.regular.monoFontSize == 12.5)
        #expect(Density.compact.monoFontSize == 11.5)
    }
}
