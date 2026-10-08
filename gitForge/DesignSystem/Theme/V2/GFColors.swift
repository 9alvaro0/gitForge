import SwiftUI

/// v2 colour tokens (redesign spec §4.1), read through `theme.colors`.
/// Coexists with the v1 `ThemePalette` until phase F9 removes it.
struct GFColors: Equatable, Sendable {
    var bgWindow: Color
    var bgContent: Color
    var bgElevated: Color
    var bgCode: Color
    var glassTint: Color
    var fillControl: Color
    var fillHover: Color
    var separator: Color
    var strokeControl: Color
    var textPrimary: Color
    var textSecondary: Color
    var textTertiary: Color
    var textQuaternary: Color
    var accent: Color
    var accentSoft: Color
    var accentFill: Color
    var accentOnFill: Color
    var add: Color
    var addSoft: Color
    var del: Color
    var delSoft: Color
    var mod: Color
    var modSoft: Color
    var warn: Color
    var warnSoft: Color
    var ok: Color
    var okSoft: Color
    var info: Color
    var infoSoft: Color
    var shadow: Color
    /// Glass surfaces render opaque (Increase Contrast). Reduce Transparency
    /// is honoured by the glass components themselves.
    var opaqueGlass: Bool

    static func make(_ variant: ThemeVariant, accent: AccentSwatch) -> GFColors {
        func pick<T>(_ dark: T, _ light: T, _ hcDark: T, _ hcLight: T) -> T {
            switch variant {
            case .dark: dark
            case .light: light
            case .highContrastDark: hcDark
            case .highContrastLight: hcLight
            }
        }
        func solid(_ dark: UInt32, _ light: UInt32, _ hcDark: UInt32, _ hcLight: UInt32) -> Color {
            Color(hex: pick(dark, light, hcDark, hcLight))
        }
        func white(_ alpha: Double) -> Color { Color(hex: 0xFFFFFF, alpha: alpha) }
        func black(_ alpha: Double) -> Color { Color(hex: 0x000000, alpha: alpha) }
        let accentForeground = accent.foreground(for: variant)

        return GFColors(
            bgWindow: solid(0x141418, 0xE8E8ED, 0x000000, 0xFFFFFF),
            bgContent: solid(0x18181C, 0xFFFFFF, 0x0A0A0C, 0xFFFFFF),
            bgElevated: solid(0x1C1C21, 0xF6F6F9, 0x121216, 0xF2F2F5),
            bgCode: solid(0x17171B, 0xFBFBFD, 0x000000, 0xFFFFFF),
            glassTint: pick(Color(hex: 0x282830, alpha: 0.62), Color(hex: 0xF8F8FB, alpha: 0.72), Color(hex: 0x16161A), Color(hex: 0xF2F2F5)),
            fillControl: pick(white(0.07), black(0.05), white(0.14), black(0.08)),
            fillHover: pick(white(0.055), black(0.04), white(0.12), black(0.08)),
            separator: pick(white(0.07), black(0.08), white(0.32), black(0.38)),
            strokeControl: pick(white(0.10), black(0.10), white(0.55), black(0.60)),
            textPrimary: solid(0xECECF1, 0x1B1B22, 0xFFFFFF, 0x000000),
            textSecondary: solid(0xB9B9C4, 0x3F3F4A, 0xE2E2EA, 0x1E1E26),
            textTertiary: solid(0xA3A3AE, 0x5A5A66, 0xCACAD4, 0x33333D),
            textQuaternary: solid(0x888893, 0x63636E, 0xB4B4C0, 0x44444F),
            accent: Color(hex: accentForeground),
            accentSoft: pick(
                Color(hex: accent.swatch, alpha: 0.24), Color(hex: accent.swatch, alpha: 0.14),
                Color(hex: accent.swatch, alpha: 0.40), Color(hex: accentForeground, alpha: 0.22)
            ),
            accentFill: Color(hex: accent.fill),
            accentOnFill: Color(hex: accent.onFill),
            add: solid(0x6FD8A4, 0x167650, 0x8CF0BE, 0x0B6B42),
            addSoft: pick(Color(hex: 0x46C88C, alpha: 0.14), Color(hex: 0x28AA6E, alpha: 0.12), Color(hex: 0x46C88C, alpha: 0.30), Color(hex: 0x0B6B42, alpha: 0.18)),
            del: solid(0xFF8A8A, 0xC8373D, 0xFFA8A8, 0xA3141B),
            delSoft: pick(Color(hex: 0xFF5F5F, alpha: 0.14), Color(hex: 0xDC3C46, alpha: 0.10), Color(hex: 0xFF5F5F, alpha: 0.30), Color(hex: 0xA3141B, alpha: 0.16)),
            mod: solid(0xF0C066, 0x9A6200, 0xFFD27A, 0x6E4500),
            modSoft: pick(Color(hex: 0xE8B04B, alpha: 0.18), Color(hex: 0xDC9614, alpha: 0.14), Color(hex: 0xE8B04B, alpha: 0.32), Color(hex: 0x6E4500, alpha: 0.16)),
            warn: solid(0xFFB547, 0xA35A00, 0xFFC56B, 0x7A4100),
            warnSoft: pick(Color(hex: 0xFFB547, alpha: 0.16), Color(hex: 0xF09614, alpha: 0.14), Color(hex: 0xFFB547, alpha: 0.32), Color(hex: 0x7A4100, alpha: 0.16)),
            ok: solid(0x5FCDA9, 0x157A5F, 0x7FE6C4, 0x0A5E47),
            okSoft: pick(Color(hex: 0x5FCDA9, alpha: 0.16), Color(hex: 0x1EA078, alpha: 0.12), Color(hex: 0x5FCDA9, alpha: 0.30), Color(hex: 0x0A5E47, alpha: 0.16)),
            info: solid(0x79B6FF, 0x1F64C8, 0x9CCBFF, 0x0A4FA8),
            infoSoft: pick(Color(hex: 0x5DA4FF, alpha: 0.16), Color(hex: 0x286EDC, alpha: 0.12), Color(hex: 0x5DA4FF, alpha: 0.30), Color(hex: 0x0A4FA8, alpha: 0.16)),
            shadow: variant.isDark ? black(0.45) : Color(hex: 0x141428, alpha: 0.14),
            opaqueGlass: variant.isHighContrast
        )
    }
}
