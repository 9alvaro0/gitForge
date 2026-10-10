import SwiftUI

/// Hashed avatar with initials. Hashes over `colorSeed` (when provided) so
/// distinct authors with the same initials still get distinguishable
/// colours. Pass the email — or any stable identity string — when you have it.
struct Avatar: View {
    let size: CGFloat
    private let initials: String
    private let background: Color

    init(name: String, size: CGFloat = 18, colorSeed: String? = nil) {
        self.size = size
        let parts = name.split(separator: " ")
        self.initials = parts.prefix(2).compactMap { $0.first.map(String.init) }.joined().uppercased()
        let lanes = ThemePalette.lanePalette
        self.background = lanes[Self.paletteIndex(seed: colorSeed ?? name, count: lanes.count)]
    }

    /// Stable palette slot for `seed`.
    static func paletteIndex(seed: String, count: Int) -> Int {
        var hash = 0
        for scalar in seed.unicodeScalars { hash = (hash &* 31) &+ Int(scalar.value) }
        return paletteIndex(hash: hash, count: count)
    }

    /// `abs(Int.min)` traps; the magnitude doesn't.
    static func paletteIndex(hash: Int, count: Int) -> Int {
        Int(hash.magnitude % UInt(count))
    }

    var body: some View {
        Text(initials)
            .font(.system(size: size * 0.45, weight: .semibold))
            // The lane hues are mid-tone in both themes; white reads on all.
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Circle().fill(background))
            .accessibilityHidden(true)
    }
}

struct RepoMark: View {
    let letter: String
    var size: CGFloat = 22

    @Environment(\.appTheme) private var theme

    var body: some View {
        Text(letter.uppercased())
            .font(.system(size: size * 0.45, weight: .bold))
            .foregroundStyle(theme.colors.accentOnFill)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: Radius.control).fill(theme.colors.accentFill))
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    VStack(spacing: Spacing.s16) {
        HStack(spacing: Spacing.s8) {
            Avatar(name: "M. Vélez")
            Avatar(name: "L. Park")
            Avatar(name: "R. Tanaka")
            Avatar(name: "A. Singh")
            Avatar(name: "Alvaro Guerra Freitas", size: 24)
        }
        HStack(spacing: Spacing.s8) {
            RepoMark(letter: "G")
            RepoMark(letter: "A")
            RepoMark(letter: "M", size: 28)
        }
    }
    .padding(Spacing.s20)
    .background(theme.colors.bgContent)
    .appTheme(theme)
}
