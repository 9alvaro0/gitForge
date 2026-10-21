import SwiftUI

/// Commit-graph lane colours (graph v3 spec §5.4). Theme-aware; HEAD's line
/// takes the accent, the trunks their fixed lanes and every other line a
/// pool colour (`color(for:accent:accentColor:dark:)`).
/// `nonisolated` because the `Canvas` renderer runs off the main actor.
nonisolated enum LaneColors {
    enum Lane: Int, CaseIterable, Sendable {
        case lane0, lane1, lane2, lane3, lane4, lane5, lane6, lane7
    }

    /// A fixed colour outside the graph (onboarding samples, chip previews).
    enum Assignment: Equatable, Sendable {
        case accent
        case lane(Lane)
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
        // The light value is 0xC08410: the old 0xC98A12 gave 2.95:1 on white, under the 3:1 minimum.
        case .lane3: dark ? 0xE8B04B : 0xC08410
        case .lane4: dark ? 0x3FC4AE : 0x0F9A85
        case .lane5: dark ? 0xC792EA : 0x8E4FD0
        case .lane6: dark ? 0x8CCF6B : 0x3F8F2A
        case .lane7: dark ? 0xF07B5A : 0xC8502C
        }
    }

    /// `Color(hex:)` is main-actor isolated; this stays callable from the renderer.
    private static func rgb(_ hex: UInt32) -> Color {
        let c = ColorMath.components(hex)
        return Color(.sRGB, red: c.r, green: c.g, blue: c.b, opacity: 1)
    }
}

// MARK: - Graph v3 palette (spec §5.4)

/// `nonisolated` on the extension itself: members of an extension take the
/// target's default main-actor isolation, not the enum's `nonisolated`.
nonisolated extension LaneColors {
    /// Lanes the graph engine hands to ordinary lines, in `GraphColorRole.pool`
    /// index order: `lane2`, `lane4`, `lane5`, `lane6` and `lane7`, minus any
    /// within 30° of the accent's hue so no other line reads as HEAD. With the
    /// blue accent `lane4` also goes. `lane0` and `lane3` are reserved for the
    /// trunks and `lane1` for HEAD, so none of them is ever a candidate.
    static func pool(accent: AccentSwatch) -> [Lane] {
        [Lane.lane2, .lane4, .lane5, .lane6, .lane7].filter {
            if accent == .blue && $0 == .lane4 { return false }
            return ColorMath.hueDistance(hex($0, dark: true), accent.swatch) >= 30
        }
    }

    /// The lane a trunk is drawn with: its fixed `lane`, or `lane4` when that
    /// colour sits within 30° of the accent's hue and would read as HEAD.
    static func trunkLane(_ lane: Lane, accent: AccentSwatch) -> Lane {
        guard lane == .lane0 || lane == .lane3 else { return lane }
        return ColorMath.hueDistance(hex(lane, dark: true), accent.swatch) < 30 ? .lane4 : lane
    }

    /// The colour a graph role is drawn with. Callable from the renderer, off
    /// the main actor.
    static func color(for role: GraphColorRole, accent: AccentSwatch, accentColor: Color, dark: Bool) -> Color {
        switch role {
        case .head:
            return accentColor
        case .main:
            return rgb(hex(trunkLane(.lane0, accent: accent), dark: dark))
        case .develop:
            return rgb(hex(trunkLane(.lane3, accent: accent), dark: dark))
        case .stash, .neutral:
            return stash(dark: dark)
        case .pool(let index):
            let lanes = pool(accent: accent)
            // Pool is never empty (3 lanes at worst); the double modulo keeps a negative index in range.
            return rgb(hex(lanes[((index % lanes.count) + lanes.count) % lanes.count], dark: dark))
        }
    }
}
