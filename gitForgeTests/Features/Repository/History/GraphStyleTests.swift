import Foundation
import SwiftUI
import Testing
@testable import gitForge

@Suite("Graph — style colours")
struct GraphStyleTests {

    private static let roles: [GraphColorRole] = [.head, .main, .develop, .stash, .neutral]
        + (-5...9).map { GraphColorRole.pool($0) }

    @Test("Each role resolves to the LaneColors colour for the style's accent and appearance",
          arguments: AccentSwatch.allCases, [true, false])
    func matchesLaneColors(accent: AccentSwatch, dark: Bool) {
        let style = GraphStyle(accent: accent, accentColor: .orange, dark: dark)
        for role in Self.roles {
            #expect(style.color(for: role)
                    == LaneColors.color(for: role, accent: accent, accentColor: .orange, dark: dark),
                    "\(role)")
        }
    }

    @Test("Two styles built from the same theme are equal, so unchanged rows skip their redraw")
    func equalAcrossRebuilds() {
        let a = GraphStyle(metrics: .compact, accent: .coral, accentColor: .orange, dark: false, nodeFill: .white)
        let b = GraphStyle(metrics: .compact, accent: .coral, accentColor: .orange, dark: false, nodeFill: .white)
        #expect(a == b)
        #expect(a != GraphStyle(metrics: .compact, accent: .blue, accentColor: .orange, dark: false, nodeFill: .white))
        #expect(a != GraphStyle(metrics: .compact, accent: .coral, accentColor: .orange, dark: true, nodeFill: .white))
    }
}
