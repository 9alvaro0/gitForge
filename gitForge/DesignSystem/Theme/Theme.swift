import SwiftUI

enum ThemeMode: String, CaseIterable, Identifiable, Sendable {
    case system
    case dark
    case light

    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: return "System"
        case .dark:   return "Dark"
        case .light:  return "Light"
        }
    }
}

/// v1 palette slots, now carrying the v2 values (see `makeDark`). New code
/// reads `theme.colors`; this goes away in phase F9.
struct ThemePalette: Equatable, Sendable {
    var bg0: Color
    var bg1: Color
    var bg2: Color
    var bg3: Color
    var bg4: Color
    var bg5: Color
    var line: Color
    var lineStrong: Color
    var fg1: Color
    var fg2: Color
    var fg3: Color
    var fg4: Color
    var accent: Color
    var accentFg: Color
    var accentSoft: Color
    var add: Color
    var addSoft: Color
    var del: Color
    var delSoft: Color
    var mod: Color
    var warn: Color
    var ok: Color
    var info: Color
    var shadowColor: Color

    static let dark: ThemePalette = .makeDark()
    static let light: ThemePalette = .makeLight()

    // Since redesign F2 the v1 slots carry the v2 values (spec §4.1), so
    // screens that still read `palette` match the restyled components until
    // they migrate to `theme.colors` (phases F3-F8). Slot mapping:
    // bg1 = window / bars, bg2 = content, bg3 = elevated surfaces,
    // bg4 / bg5 = hover / active fills, fg1-fg4 = text primary-quaternary.
    private static func makeDark() -> ThemePalette {
        var p = ThemePalette.empty
        p.bg0 = Color(hex: 0x101013)
        p.bg1 = Color(hex: 0x141418)
        p.bg2 = Color(hex: 0x18181C)
        p.bg3 = Color(hex: 0x1C1C21)
        p.bg4 = Color(hex: 0x232329)
        p.bg5 = Color(hex: 0x2A2A31)
        p.line = Color.white.opacity(0.07)
        p.lineStrong = Color.white.opacity(0.10)
        p.fg1 = Color(hex: 0xECECF1)
        p.fg2 = Color(hex: 0xB9B9C4)
        p.fg3 = Color(hex: 0xA3A3AE)
        p.fg4 = Color(hex: 0x888893)
        p.accent = Color(hex: 0x7350FA)
        p.accentFg = .white
        p.accentSoft = Color(hex: 0x7C5CFF, alpha: 0.24)
        p.add = Color(hex: 0x6FD8A4)
        p.addSoft = Color(hex: 0x46C88C, alpha: 0.14)
        p.del = Color(hex: 0xFF8A8A)
        p.delSoft = Color(hex: 0xFF5F5F, alpha: 0.14)
        p.mod = Color(hex: 0xF0C066)
        p.warn = Color(hex: 0xFFB547)
        p.ok = Color(hex: 0x5FCDA9)
        p.info = Color(hex: 0x79B6FF)
        p.shadowColor = Color.black.opacity(0.45)
        return p
    }

    private static func makeLight() -> ThemePalette {
        var p = ThemePalette.empty
        p.bg0 = Color(hex: 0xE8E8ED)
        p.bg1 = Color(hex: 0xF6F6F9)
        p.bg2 = Color(hex: 0xFFFFFF)
        p.bg3 = Color(hex: 0xF2F2F5)
        p.bg4 = Color(hex: 0xEBEBEF)
        p.bg5 = Color(hex: 0xE3E3E8)
        p.line = Color.black.opacity(0.08)
        p.lineStrong = Color.black.opacity(0.12)
        p.fg1 = Color(hex: 0x1B1B22)
        p.fg2 = Color(hex: 0x3F3F4A)
        p.fg3 = Color(hex: 0x5A5A66)
        p.fg4 = Color(hex: 0x63636E)
        p.accent = Color(hex: 0x7350FA)
        p.accentFg = .white
        p.accentSoft = Color(hex: 0x7C5CFF, alpha: 0.14)
        p.add = Color(hex: 0x167650)
        p.addSoft = Color(hex: 0x28AA6E, alpha: 0.12)
        p.del = Color(hex: 0xC8373D)
        p.delSoft = Color(hex: 0xDC3C46, alpha: 0.10)
        p.mod = Color(hex: 0x9A6200)
        p.warn = Color(hex: 0xA35A00)
        p.ok = Color(hex: 0x157A5F)
        p.info = Color(hex: 0x1F64C8)
        p.shadowColor = Color(hex: 0x141428, alpha: 0.14)
        return p
    }

    private static var empty: ThemePalette {
        ThemePalette(
            bg0: .clear, bg1: .clear, bg2: .clear, bg3: .clear, bg4: .clear, bg5: .clear,
            line: .clear, lineStrong: .clear,
            fg1: .clear, fg2: .clear, fg3: .clear, fg4: .clear,
            accent: .clear, accentFg: .clear, accentSoft: .clear,
            add: .clear, addSoft: .clear, del: .clear, delSoft: .clear,
            mod: .clear, warn: .clear, ok: .clear, info: .clear,
            shadowColor: .clear
        )
    }

    /// - Parameter highContrast: the system's "Increase contrast" setting:
    ///   swaps in the v2 increased-contrast values (spec §4.1).
    /// - Parameter accent: the stored accent; it maps to its v2 swatch, whose
    ///   deepened fill keeps white text legible.
    static func palette(for mode: ThemeMode, accent: Color, highContrast: Bool = false) -> ThemePalette {
        let dark = mode == .dark
        var base = dark ? Self.dark : Self.light
        let swatch = AccentSwatch.nearest(toHex: Self.hex(of: accent))
        base.accent = Color(hex: swatch.fill)
        base.accentFg = Color(hex: swatch.onFill)
        base.accentSoft = Color(hex: swatch.swatch, alpha: dark ? 0.24 : 0.14)
        if highContrast {
            base.applyHighContrast(dark: dark)
        }
        return base
    }

    private static func hex(of color: Color) -> UInt32 {
        guard let c = NSColor(color).usingColorSpace(.sRGB) else { return AccentSwatch.violet.swatch }
        return ColorMath.hex(r: Double(c.redComponent), g: Double(c.greenComponent), b: Double(c.blueComponent))
    }

    private mutating func applyHighContrast(dark: Bool) {
        if dark {
            bg0 = Color(hex: 0x000000)
            bg1 = Color(hex: 0x000000)
            bg2 = Color(hex: 0x0A0A0C)
            bg3 = Color(hex: 0x121216)
            fg1 = Color(hex: 0xFFFFFF)
            fg2 = Color(hex: 0xE2E2EA)
            fg3 = Color(hex: 0xCACAD4)
            fg4 = Color(hex: 0xB4B4C0)
            line = Color.white.opacity(0.32)
            lineStrong = Color.white.opacity(0.55)
            add = Color(hex: 0x8CF0BE)
            del = Color(hex: 0xFFA8A8)
            mod = Color(hex: 0xFFD27A)
            warn = Color(hex: 0xFFC56B)
            ok = Color(hex: 0x7FE6C4)
            info = Color(hex: 0x9CCBFF)
        } else {
            bg0 = Color(hex: 0xFFFFFF)
            bg1 = Color(hex: 0xF2F2F5)
            bg2 = Color(hex: 0xFFFFFF)
            bg3 = Color(hex: 0xF2F2F5)
            fg1 = Color(hex: 0x000000)
            fg2 = Color(hex: 0x1E1E26)
            fg3 = Color(hex: 0x33333D)
            fg4 = Color(hex: 0x44444F)
            line = Color.black.opacity(0.38)
            lineStrong = Color.black.opacity(0.60)
            add = Color(hex: 0x0B6B42)
            del = Color(hex: 0xA3141B)
            mod = Color(hex: 0x6E4500)
            warn = Color(hex: 0x7A4100)
            ok = Color(hex: 0x0A5E47)
            info = Color(hex: 0x0A4FA8)
        }
    }

    /// Hashed swatch palette used wherever we need to distinguish identities
    /// at a glance: avatar backgrounds, lane highlighting, brand gradients.
    /// Order matters — re-ordering reshuffles the avatar colour for existing
    /// authors whose name hashes into a different slot.
    static let lanePalette: [Color] = [
        Color(hex: 0x7c5cff),
        Color(hex: 0xff7e6b),
        Color(hex: 0x56b497),
        Color(hex: 0xdda44b),
        Color(hex: 0x5da4ff),
        Color(hex: 0xc976d9),
    ]
}
