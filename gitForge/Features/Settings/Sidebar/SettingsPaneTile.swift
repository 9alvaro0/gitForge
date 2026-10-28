import SwiftUI

/// A pane's tinted square: its glyph in the pane's colour over a soft fill of
/// the same hue. The Settings sidebar draws it at 22 pt; the pane headers
/// reuse it larger (settings-redesign S2).
struct SettingsPaneTile: View {
    let pane: SettingsPane
    let size: CGFloat

    @Environment(\.appTheme) private var theme

    /// Glyph and fill of a pane's tile.
    struct Palette {
        let foreground: Color
        let background: Color
    }

    var body: some View {
        let palette = Self.palette(for: pane, variant: theme.variant, colors: theme.colors)
        RoundedRectangle(cornerRadius: size * Self.cornerRatio)
            .fill(palette.background)
            .frame(width: size, height: size)
            .overlay {
                SymbolGlyph(pane.symbol, size: size * Self.glyphRatio)
                    .foregroundStyle(palette.foreground)
            }
            .accessibilityHidden(true)
    }

    /// Corner radius over side: 6 pt on a 22 pt tile, 10 pt on a 40 pt one.
    private static let cornerRatio: CGFloat = 0.27
    /// Glyph box over side, so a 22 pt tile holds a 14 pt glyph.
    private static let glyphRatio: CGFloat = 0.64

    /// General, Accounts and Pull requests take the theme's own neutral, info
    /// and warn tokens, which have a soft fill. The other three have none, so
    /// their fill is the glyph colour at 14% in light and 24% in dark, the
    /// same weights the accent's soft fill uses.
    static func palette(for pane: SettingsPane, variant: ThemeVariant, colors: GFColors) -> Palette {
        func tinted(_ hex: UInt32) -> Palette {
            Palette(foreground: Color(hex: hex),
                    background: Color(hex: hex, alpha: variant.isDark ? 0.24 : 0.14))
        }
        switch pane {
        case .general:
            return Palette(foreground: colors.textSecondary, background: colors.fillControl)
        case .appearance:
            return tinted(AccentSwatch.violet.foreground(for: variant))
        case .identities:
            // `LaneColors` only knows dark and light: the high-contrast
            // variants take the plain one of their kind.
            return tinted(LaneColors.hex(.lane2, dark: variant.isDark))
        case .accounts:
            return Palette(foreground: colors.info, background: colors.infoSoft)
        case .git:
            return tinted(AccentSwatch.coral.foreground(for: variant))
        case .pullRequests:
            return Palette(foreground: colors.warn, background: colors.warnSoft)
        }
    }
}

#Preview("Tiles") {
    @Previewable @State var theme = AppTheme()
    VStack(alignment: .leading, spacing: Spacing.s12) {
        ForEach([22.0, 40.0], id: \.self) { size in
            HStack(spacing: Spacing.s8) {
                ForEach(SettingsPane.allCases) { pane in
                    SettingsPaneTile(pane: pane, size: size)
                }
            }
        }
    }
    .padding(Spacing.s16)
    .background(theme.colors.bgWindow)
    .appTheme(theme)
}
