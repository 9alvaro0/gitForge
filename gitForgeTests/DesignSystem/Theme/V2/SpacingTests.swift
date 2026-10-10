import Foundation
import Testing
@testable import gitForge

@Suite("Spacing and Radius v2")
struct SpacingTests {

    @Test("Spacing scale matches the sheet, grows strictly and stays on even points")
    func spacing() {
        let scale = [Spacing.s2, Spacing.s4, Spacing.s6, Spacing.s8, Spacing.s12,
                     Spacing.s16, Spacing.s20, Spacing.s24, Spacing.s32, Spacing.s48]
        #expect(scale == [2, 4, 6, 8, 12, 16, 20, 24, 32, 48])
        #expect(scale.allSatisfy { $0.truncatingRemainder(dividingBy: 2) == 0 })
    }

    @Test("Radii match the sheet and grow strictly")
    func radius() {
        let scale = [Radius.badge, Radius.chip, Radius.controlSmall, Radius.row,
                     Radius.control, Radius.card, Radius.popover, Radius.panel]
        #expect(scale == [4, 5, 6, 7, 8, 12, 14, 18])
        #expect(zip(scale, scale.dropFirst()).allSatisfy { $0 < $1 })
    }
}
