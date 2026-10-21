import Foundation
import Testing
@testable import gitForge

@Suite("LaneColors")
struct LaneColorsTests {

    @Test("HEAD takes the accent, even when it is main")
    func headWins() {
        #expect(LaneColors.assignment(branchId: 7, priorityRank: nil, isHead: true, accent: .violet) == .accent)
        #expect(LaneColors.assignment(branchId: 0, priorityRank: 0, isHead: true, accent: .violet) == .accent)
    }

    @Test("Trunks are pinned: main to lane 0, develop to lane 3")
    func trunks() {
        #expect(LaneColors.assignment(branchId: 9, priorityRank: 0, isHead: false, accent: .violet) == .lane(.lane0))
        #expect(LaneColors.assignment(branchId: 9, priorityRank: 1, isHead: false, accent: .violet) == .lane(.lane3))
    }

    @Test("A pinned trunk keeps its lane even when the accent skips it")
    func trunkBeatsSkip() {
        #expect(LaneColors.assignment(branchId: 1, priorityRank: 0, isHead: false, accent: .blue) == .lane(.lane0))
    }

    @Test("The pool drops lanes near the accent's hue",
          arguments: [(AccentSwatch.blue, LaneColors.Lane.lane0), (.coral, .lane2), (.green, .lane4)])
    func skipsNearAccent(accent: AccentSwatch, skipped: LaneColors.Lane) {
        #expect(!LaneColors.hashPool(accent: accent).contains(skipped))
    }

    @Test("Hashed branches never take lane 1 or a lane within 30° of the accent", arguments: AccentSwatch.allCases)
    func hashedLanes(accent: AccentSwatch) {
        for id in -50..<200 {
            guard case .lane(let lane) = LaneColors.assignment(branchId: id, priorityRank: nil, isHead: false, accent: accent) else {
                Issue.record("branch \(id) got the accent"); return
            }
            #expect(lane != .lane1)
            #expect(ColorMath.hueDistance(LaneColors.hex(lane, dark: true), accent.swatch) >= 30)
        }
    }

    @Test("Assignment is stable and survives extreme ids")
    func stable() {
        let a = LaneColors.assignment(branchId: 42, priorityRank: nil, isHead: false, accent: .violet)
        #expect(a == LaneColors.assignment(branchId: 42, priorityRank: nil, isHead: false, accent: .violet))
        _ = LaneColors.assignment(branchId: .min, priorityRank: nil, isHead: false, accent: .violet)
        _ = LaneColors.assignment(branchId: .max, priorityRank: 2, isHead: false, accent: .blue)
    }

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
}
