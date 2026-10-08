import AppKit
import SwiftUI
import Testing
@testable import gitForge

/// WCAG contrast guard for the palette. The app's text is 10–12pt, so the
/// bar is AA for normal text: 4.5:1 against every background it sits on.
/// If a redesign edits the palette, these say which pairs regressed.
@Suite("ThemePalette — contrast")
@MainActor
struct PaletteContrastTests {

    private static func luminance(_ color: Color) -> Double {
        let c = NSColor(color).usingColorSpace(.sRGB)!
        func channel(_ v: CGFloat) -> Double {
            let v = Double(v)
            return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(c.redComponent) + 0.7152 * channel(c.greenComponent) + 0.0722 * channel(c.blueComponent)
    }

    private static func contrast(_ a: Color, _ b: Color) -> Double {
        let (la, lb) = (luminance(a), luminance(b))
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    private static func worst(_ fg: Color, on palette: ThemePalette) -> Double {
        [palette.bg1, palette.bg2, palette.bg3].map { contrast(fg, $0) }.min()!
    }

    @Test("Primary and secondary text meet AA in both themes", arguments: [ThemeMode.dark, .light])
    func primaryText(mode: ThemeMode) {
        let palette = ThemePalette.palette(for: mode, accent: Color(hex: 0x7c5cff))
        #expect(Self.worst(palette.fg1, on: palette) >= 4.5)
        #expect(Self.worst(palette.fg2, on: palette) >= 4.5)
    }

    @Test("Increase Contrast lifts every text and status colour to AA", arguments: [ThemeMode.dark, .light])
    func highContrast(mode: ThemeMode) {
        let palette = ThemePalette.palette(for: mode, accent: Color(hex: 0x7c5cff), highContrast: true)
        let named: [(String, Color)] = [
            ("fg1", palette.fg1), ("fg2", palette.fg2), ("fg3", palette.fg3), ("fg4", palette.fg4),
            ("add", palette.add), ("del", palette.del), ("mod", palette.mod),
            ("warn", palette.warn), ("ok", palette.ok), ("info", palette.info),
        ]
        for (name, color) in named {
            #expect(Self.worst(color, on: palette) >= 4.5, "\(mode) \(name)")
        }
    }
}
