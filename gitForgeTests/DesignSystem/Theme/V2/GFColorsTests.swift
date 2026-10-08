import AppKit
import SwiftUI
import Testing
@testable import gitForge

/// WCAG guard for the v2 palette (redesign spec §8). Every text token must
/// reach AA (4.5:1) on bg.content and bg.elevated in all four variants.
@Suite("GFColors")
@MainActor
struct GFColorsTests {

    private static func hex(_ color: Color) -> UInt32 {
        let c = NSColor(color).usingColorSpace(.sRGB)!
        return ColorMath.hex(r: Double(c.redComponent), g: Double(c.greenComponent), b: Double(c.blueComponent))
    }

    private static func textTokens(_ colors: GFColors) -> [(String, Color)] {
        [
            ("textPrimary", colors.textPrimary), ("textSecondary", colors.textSecondary),
            ("textTertiary", colors.textTertiary), ("textQuaternary", colors.textQuaternary),
            ("accent", colors.accent), ("add", colors.add), ("del", colors.del), ("mod", colors.mod),
            ("warn", colors.warn), ("ok", colors.ok), ("info", colors.info),
        ]
    }

    @Test("Every text token meets AA on bg.content and bg.elevated", arguments: ThemeVariant.allCases)
    func textContrast(variant: ThemeVariant) {
        for swatch in AccentSwatch.allCases {
            let colors = GFColors.make(variant, accent: swatch)
            let backgrounds = [Self.hex(colors.bgContent), Self.hex(colors.bgElevated)]
            for (name, token) in Self.textTokens(colors) {
                let worst = backgrounds.map { ColorMath.contrast(Self.hex(token), $0) }.min()!
                #expect(worst >= 4.5, "\(variant) \(swatch) \(name): \(worst)")
            }
        }
    }

    @Test("Values match the design sheet")
    func sheetValues() {
        let dark = GFColors.make(.dark, accent: .violet)
        #expect(Self.hex(dark.bgWindow) == 0x141418)
        #expect(Self.hex(dark.textQuaternary) == 0x888893)
        #expect(Self.hex(dark.accent) == 0xA08CFF)
        #expect(Self.hex(dark.accentFill) == 0x7350FA)
        let light = GFColors.make(.light, accent: .blue)
        #expect(Self.hex(light.bgElevated) == 0xF6F6F9)
        #expect(Self.hex(light.warn) == 0xA35A00)
        #expect(Self.hex(light.accent) == 0x1F66CC)
        #expect(Self.hex(light.accentOnFill) == 0x101014)
    }

    @Test("Glass turns opaque only with Increase Contrast")
    func opaqueGlass() {
        #expect(!GFColors.make(.dark, accent: .violet).opaqueGlass)
        #expect(!GFColors.make(.light, accent: .violet).opaqueGlass)
        #expect(GFColors.make(.highContrastDark, accent: .violet).opaqueGlass)
        #expect(GFColors.make(.highContrastLight, accent: .violet).opaqueGlass)
    }
}
