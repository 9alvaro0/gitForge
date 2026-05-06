import SwiftUI

enum ThemeMode: String, CaseIterable, Identifiable, Sendable {
    case dark
    case light

    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

/// Direct port of the `:root[data-theme="…"]` CSS variables from the design bundle.
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

    private static func makeDark() -> ThemePalette {
        var p = ThemePalette.empty
        p.bg0 = Color(hex: 0x0a0910)
        p.bg1 = Color(hex: 0x0f0e16)
        p.bg2 = Color(hex: 0x14121c)
        p.bg3 = Color(hex: 0x1a1825)
        p.bg4 = Color(hex: 0x221f2e)
        p.bg5 = Color(hex: 0x2a2638)
        p.line = Color(hex: 0x272434, alpha: 0.25)
        p.lineStrong = Color(hex: 0x2f2c40)
        p.fg1 = Color(hex: 0xf0eff5)
        p.fg2 = Color(hex: 0xb9b6c8)
        p.fg3 = Color(hex: 0x7d7a8e)
        p.fg4 = Color(hex: 0x4a475a)
        p.accent = Color(hex: 0x7c5cff)
        p.accentFg = .white
        p.accentSoft = Color(hex: 0x7c5cff, alpha: 0.13)
        p.add = Color(hex: 0x56b497)
        p.addSoft = Color(hex: 0x56b497, alpha: 0.10)
        p.del = Color(hex: 0xff7e6b)
        p.delSoft = Color(hex: 0xff7e6b, alpha: 0.10)
        p.mod = Color(hex: 0xdda44b)
        p.warn = Color(hex: 0xf5b042)
        p.ok = Color(hex: 0x56b497)
        p.info = Color(hex: 0x5da4ff)
        p.shadowColor = Color.black.opacity(0.55)
        return p
    }

    private static func makeLight() -> ThemePalette {
        var p = ThemePalette.empty
        p.bg0 = Color(hex: 0xe6e4ec)
        p.bg1 = Color(hex: 0xf4f3f7)
        p.bg2 = Color(hex: 0xfbfafc)
        p.bg3 = Color(hex: 0xffffff)
        p.bg4 = Color(hex: 0xefedf3)
        p.bg5 = Color(hex: 0xe3e0eb)
        p.line = Color.black.opacity(0.06)
        p.lineStrong = Color.black.opacity(0.10)
        p.fg1 = Color(hex: 0x1a1825)
        p.fg2 = Color(hex: 0x4a475a)
        p.fg3 = Color(hex: 0x6e6b80)
        p.fg4 = Color(hex: 0xa09db0)
        p.accent = Color(hex: 0x7c5cff)
        p.accentFg = .white
        p.accentSoft = Color(hex: 0x7c5cff, alpha: 0.10)
        p.add = Color(hex: 0x1f8a5b)
        p.addSoft = Color(hex: 0x1f8a5b, alpha: 0.08)
        p.del = Color(hex: 0xd05a4a)
        p.delSoft = Color(hex: 0xd05a4a, alpha: 0.08)
        p.mod = Color(hex: 0xb07a1a)
        p.warn = Color(hex: 0xb07a1a)
        p.ok = Color(hex: 0x1f8a5b)
        p.info = Color(hex: 0x2f6dd6)
        p.shadowColor = Color.black.opacity(0.18)
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

    static func palette(for mode: ThemeMode, accent: Color) -> ThemePalette {
        var base = mode == .dark ? Self.dark : Self.light
        base.accent = accent
        base.accentSoft = accent.opacity(mode == .dark ? 0.13 : 0.10)
        return base
    }

    /// Lane palette used by commit graph + blame highlighting.
    static let lanePalette: [Color] = [
        Color(hex: 0x7c5cff),
        Color(hex: 0x56b497),
        Color(hex: 0xff7e6b),
        Color(hex: 0xdda44b),
        Color(hex: 0x5da4ff),
        Color(hex: 0xc976d9),
    ]
}
