import SwiftUI

/// Hashed avatar with initials. Matches `Avatar` from components.jsx but
/// hashes over `colorSeed` (when provided) so distinct authors with the same
/// initials still get distinguishable bg colors. Pass the email — or any
/// stable identity string — when you have it.
struct Avatar: View {
    let name: String
    var size: CGFloat = 18
    var colorSeed: String? = nil

    @Environment(\.appTheme) private var theme

    var body: some View {
        Text(initials)
            .font(.system(size: size * 0.5, weight: .bold))
            .foregroundStyle(theme.palette.accentFg)
            .frame(width: size, height: size)
            .background(Circle().fill(background))
    }

    private var initials: String {
        let parts = name.split(separator: " ")
        return parts.prefix(2).compactMap { $0.first.map(String.init) }.joined().uppercased()
    }

    private var background: Color {
        let seed = colorSeed ?? name
        var h: Int = 0
        for c in seed.unicodeScalars { h = (h &* 31) &+ Int(c.value) }
        let palette = ThemePalette.lanePalette
        return palette[abs(h) % palette.count]
    }
}

/// `.gf-repo-mark` — square colored mark with the org's first letter.
struct RepoMark: View {
    let letter: String
    var size: CGFloat = 22

    @Environment(\.appTheme) private var theme

    var body: some View {
        Text(letter.uppercased())
            .font(.system(size: size * 0.5, weight: .bold))
            .foregroundStyle(theme.palette.accent)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: 5).fill(theme.palette.accentSoft))
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    VStack(spacing: DesignTokens.Spacing.xl) {
        HStack(spacing: DesignTokens.Spacing.md) {
            Avatar(name: "M. Vélez")
            Avatar(name: "L. Park")
            Avatar(name: "R. Tanaka")
            Avatar(name: "A. Singh")
            Avatar(name: "Alvaro Guerra Freitas", size: 24)
        }
        HStack(spacing: DesignTokens.Spacing.md) {
            RepoMark(letter: "G")
            RepoMark(letter: "A")
            RepoMark(letter: "M", size: 28)
        }
    }
    .padding(DesignTokens.Spacing.huge)
    .background(theme.palette.bg2)
    .appTheme(theme)
}
