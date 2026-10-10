import SwiftUI

/// v2 commit-graph lane colours (redesign spec §4.5). Theme-aware, unlike
/// the v1 `GraphPalette`, and the HEAD branch always takes the accent.
/// `nonisolated` because the `Canvas` renderer runs off the main actor.
nonisolated enum LaneColors {
    enum Lane: Int, CaseIterable, Sendable {
        case lane0, lane1, lane2, lane3, lane4, lane5
    }

    enum Assignment: Equatable, Sendable {
        case accent
        case lane(Lane)
    }

    /// Lanes a hashed (non-HEAD, non-trunk) branch may take. Lane 1 is
    /// reserved for HEAD, and any lane within 30° of the accent's hue is
    /// skipped so no other branch reads as HEAD.
    static func hashPool(accent: AccentSwatch) -> [Lane] {
        [Lane.lane0, .lane2, .lane3, .lane4, .lane5].filter {
            ColorMath.hueDistance(hex($0, dark: true), accent.swatch) >= 30
        }
    }

    /// - Parameter priorityRank: trunk rank from the layout, as in
    ///   `GraphPalette.color(branchId:priorityRank:)`: 0 main/master, 1 develop.
    static func assignment(branchId: Int, priorityRank: Int?, isHead: Bool, accent: AccentSwatch) -> Assignment {
        if isHead { return .accent }
        switch priorityRank {
        case 0: return .lane(.lane0)
        case 1: return .lane(.lane3)
        default:
            let pool = hashPool(accent: accent)
            let index = ((branchId % pool.count) + pool.count) % pool.count
            return .lane(pool[index])
        }
    }

    static func color(_ assignment: Assignment, dark: Bool, accent: Color) -> Color {
        switch assignment {
        case .accent: accent
        case .lane(let lane): rgb(hex(lane, dark: dark))
        }
    }

    static func stash(dark: Bool) -> Color {
        rgb(dark ? 0x8E8E99 : 0x9A9AA6)
    }

    static func hex(_ lane: Lane, dark: Bool) -> UInt32 {
        switch lane {
        case .lane0: dark ? 0x5AA9FF : 0x2F86EA
        // Violet reference only: HEAD normally resolves through `.accent`.
        case .lane1: dark ? 0xA08CFF : 0x5B3DF5
        case .lane2: dark ? 0xF0729E : 0xD6457F
        case .lane3: dark ? 0xE8B04B : 0xC98A12
        case .lane4: dark ? 0x3FC4AE : 0x0F9A85
        case .lane5: dark ? 0xC792EA : 0x8E4FD0
        }
    }

    /// `Color(hex:)` is main-actor isolated; this stays callable from the renderer.
    private static func rgb(_ hex: UInt32) -> Color {
        let c = ColorMath.components(hex)
        return Color(.sRGB, red: c.r, green: c.g, blue: c.b, opacity: 1)
    }
}
