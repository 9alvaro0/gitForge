import Foundation
import Testing
@testable import gitForge

@Suite("FontSize scale")
@MainActor
struct TypographyScaleTests {

    @Test("Steps are strictly increasing, so a mistyped token can't silently swap two sizes")
    func strictlyIncreasing() {
        let scale: [CGFloat] = [
            FontSize.xxs, FontSize.xs, FontSize.sm, FontSize.smPlus, FontSize.md, FontSize.mdPlus,
            FontSize.lg, FontSize.xl, FontSize.xxl, FontSize.xxxl, FontSize.title,
            FontSize.largeTitle, FontSize.display,
        ]
        #expect(zip(scale, scale.dropFirst()).allSatisfy { $0 < $1 })
    }

    @Test("Detail pane titles use a step of the scale")
    func detailTitleOnScale() {
        #expect(DesignTokens.Detail.titleFontSize == FontSize.xxxl)
    }
}
