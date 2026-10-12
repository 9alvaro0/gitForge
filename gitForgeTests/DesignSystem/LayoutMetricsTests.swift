import CoreGraphics
import Testing
@testable import gitForge

@Suite("LayoutMetrics")
struct LayoutMetricsTests {
    @Test("Onboarding side margin: the artboard's 96 on a wide column, 48 otherwise")
    func onboardingGutter() {
        #expect(LayoutMetrics.onboardingGutter(columnWidth: 800) == Spacing.s48)
        #expect(LayoutMetrics.onboardingGutter(columnWidth: 999) == Spacing.s48)
        #expect(LayoutMetrics.onboardingGutter(columnWidth: 1000) == 96)
    }
}
