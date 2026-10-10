import AppKit
import SwiftUI
import Testing
@testable import gitForge

@Suite("SyntaxPalette")
@MainActor
struct SyntaxPaletteTests {

    private static func hex(_ color: Color) -> UInt32 {
        let c = NSColor(color).usingColorSpace(.sRGB)!
        return ColorMath.hex(r: Double(c.redComponent), g: Double(c.greenComponent), b: Double(c.blueComponent))
    }

    @Test("Every code colour meets AA on bg.code", arguments: ThemeVariant.allCases)
    func contrast(variant: ThemeVariant) {
        let code = Self.hex(GFColors.make(variant, accent: .violet).bgCode)
        for (name, color) in SyntaxPalette.make(variant).all {
            let ratio = ColorMath.contrast(color, code)
            #expect(ratio >= 4.5, "\(variant) \(name): \(ratio)")
        }
    }

    @Test("The CSS sheet carries the palette and never paints backgrounds")
    func css() {
        let sheet = DiffSyntaxHighlighter.css(for: .dark)
        #expect(sheet.contains("#FF7AB2"))
        #expect(sheet.contains("#DCDCE4"))
        #expect(!sheet.contains("background"))
    }
}
