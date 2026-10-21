import Foundation
import SwiftUI
import Testing
@testable import gitForge

@Suite("LaneColors")
struct LaneColorsTests {

    @Test("Lane colours follow the theme")
    func themed() {
        #expect(LaneColors.hex(.lane0, dark: true) == 0x5AA9FF)
        #expect(LaneColors.hex(.lane0, dark: false) == 0x2F86EA)
        #expect(LaneColors.hex(.lane5, dark: false) == 0x8E4FD0)
    }

    @Test("The pool per accent", arguments: [
        (AccentSwatch.violet, [LaneColors.Lane.lane2, .lane4, .lane6, .lane7]),
        (.green, [.lane2, .lane5, .lane6, .lane7]),
        (.coral, [.lane4, .lane5, .lane6]),
        (.blue, [.lane2, .lane5, .lane6, .lane7]),
    ])
    func pool(accent: AccentSwatch, expected: [LaneColors.Lane]) {
        #expect(LaneColors.pool(accent: accent) == expected)
    }

    @Test("A trunk too close to the accent switches to lane 4")
    func trunkSwap() {
        #expect(LaneColors.trunkLane(.lane0, accent: .blue) == .lane4)
        #expect(LaneColors.trunkLane(.lane0, accent: .violet) == .lane0)
        #expect(LaneColors.trunkLane(.lane3, accent: .coral) == .lane3)
    }

    @Test("Every graph lane reaches 3:1 on the content background", arguments: [true, false])
    func graphicsContrast(dark: Bool) {
        let background: UInt32 = dark ? 0x18181C : 0xFFFFFF
        for lane in LaneColors.Lane.allCases where lane != .lane1 {
            #expect(ColorMath.contrast(LaneColors.hex(lane, dark: dark), background) >= 3, "\(lane) dark=\(dark)")
        }
    }

    @Test("New and changed lane values")
    func newValues() {
        #expect(LaneColors.hex(.lane6, dark: true) == 0x8CCF6B && LaneColors.hex(.lane6, dark: false) == 0x3F8F2A)
        #expect(LaneColors.hex(.lane7, dark: true) == 0xF07B5A && LaneColors.hex(.lane7, dark: false) == 0xC8502C)
        #expect(LaneColors.hex(.lane3, dark: false) == 0xC08410)
    }

    // MARK: color(for:)

    private static func color(_ role: GraphColorRole, accent: AccentSwatch = .violet,
                              accentColor: Color = .red, dark: Bool = true) -> Color {
        LaneColors.color(for: role, accent: accent, accentColor: accentColor, dark: dark)
    }

    private static func lane(_ lane: LaneColors.Lane, dark: Bool = true) -> Color {
        LaneColors.color(.lane(lane), dark: dark, accent: .red)
    }

    @Test("A pool role wraps modulo the pool count", arguments: AccentSwatch.allCases)
    func poolWraps(accent: AccentSwatch) {
        let lanes = LaneColors.pool(accent: accent)
        for index in lanes.indices {
            #expect(Self.color(.pool(index), accent: accent) == Self.lane(lanes[index]))
            #expect(Self.color(.pool(index + lanes.count), accent: accent) == Self.lane(lanes[index]))
            #expect(Self.color(.pool(index + 7 * lanes.count), accent: accent) == Self.lane(lanes[index]))
        }
    }

    @Test("A negative pool index stays in range")
    func negativePoolIndex() {
        let lanes = LaneColors.pool(accent: .violet)
        #expect(Self.color(.pool(-1)) == Self.lane(lanes[lanes.count - 1]))
        #expect(Self.color(.pool(-lanes.count)) == Self.lane(lanes[0]))
        _ = Self.color(.pool(.min))
    }

    @Test("Main with the blue accent takes lane 4; with violet it keeps lane 0")
    func mainUnderBlue() {
        #expect(Self.color(.main, accent: .blue) == Self.lane(.lane4))
        #expect(Self.color(.main, accent: .blue, dark: false) == Self.lane(.lane4, dark: false))
        #expect(Self.color(.main, accent: .violet) == Self.lane(.lane0))
        #expect(Self.color(.develop, accent: .violet) == Self.lane(.lane3))
    }

    @Test("HEAD takes the accent colour passed in")
    func head() {
        #expect(Self.color(.head, accentColor: .orange) == .orange)
        #expect(Self.color(.head, accentColor: .mint) == .mint)
    }

    @Test("Stash and neutral both take the stash grey", arguments: [true, false])
    func stashAndNeutral(dark: Bool) {
        #expect(Self.color(.stash, dark: dark) == LaneColors.stash(dark: dark))
        #expect(Self.color(.neutral, dark: dark) == LaneColors.stash(dark: dark))
    }
}
