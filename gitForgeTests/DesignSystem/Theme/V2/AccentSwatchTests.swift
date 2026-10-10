import Foundation
import Testing
@testable import gitForge

@Suite("AccentSwatch")
struct AccentSwatchTests {

    @Test("Variant resolves from the effective scheme and Increase Contrast")
    func variant() {
        #expect(ThemeVariant(isDark: true, highContrast: false) == .dark)
        #expect(ThemeVariant(isDark: false, highContrast: false) == .light)
        #expect(ThemeVariant(isDark: true, highContrast: true) == .highContrastDark)
        #expect(ThemeVariant(isDark: false, highContrast: true) == .highContrastLight)
    }

    @Test("Swatch values match the design sheet")
    func values() {
        #expect(AccentSwatch.violet.fill == 0x7350FA)
        #expect(AccentSwatch.violet.onFill == 0xFFFFFF)
        #expect(AccentSwatch.green.onFill == 0x101014)
        #expect(AccentSwatch.coral.foreground(for: .dark) == 0xFF907F)
        #expect(AccentSwatch.blue.foreground(for: .light) == 0x1F66CC)
        #expect(AccentSwatch.violet.foreground(for: .highContrastDark) == 0xBBAAFF)
        #expect(AccentSwatch.violet.foreground(for: .highContrastLight) == 0x4321D9)
    }

    @Test("Text on the accent fill meets AA for every swatch", arguments: AccentSwatch.allCases)
    func onFillContrast(swatch: AccentSwatch) {
        #expect(ColorMath.contrast(swatch.onFill, swatch.fill) >= 4.5)
    }

    @Test("High-contrast foregrounds reach 7:1 on bg.content", arguments: AccentSwatch.allCases)
    func highContrastForeground(swatch: AccentSwatch) {
        for variant in [ThemeVariant.highContrastDark, .highContrastLight] {
            #expect(ColorMath.contrast(swatch.foreground(for: variant), variant.contentBackground) >= 7, "\(swatch) \(variant)")
        }
    }

    @Test("A stored swatch maps to itself")
    func exactMatch() {
        for swatch in AccentSwatch.allCases {
            #expect(AccentSwatch.nearest(toHex: swatch.swatch) == swatch)
        }
    }

    @Test("Any other colour maps to the swatch with the closest hue, greys included")
    func nearest() {
        #expect(AccentSwatch.nearest(toHex: 0x0000FF) == .violet)
        #expect(AccentSwatch.nearest(toHex: 0x2080FF) == .blue)
        #expect(AccentSwatch.nearest(toHex: 0x00C080) == .green)
        #expect(AccentSwatch.nearest(toHex: 0xFF0000) == .coral)
        #expect(AccentSwatch.allCases.contains(AccentSwatch.nearest(toHex: 0x808080)))
    }
}
