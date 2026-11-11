import SwiftUI

/// Hashed avatar with initials (`AuthorMonogram`). Hashes over `colorSeed`
/// (when provided) so distinct authors with the same initials still get
/// distinguishable colours. Pass the email — or any stable identity string —
/// when you have it. A commit's author goes through `AuthorAvatar`, which
/// swaps in the host's picture when there is one.
struct Avatar: View {
    let size: CGFloat
    private let initials: String
    private let background: Color

    init(name: String, size: CGFloat = 18, colorSeed: String? = nil) {
        self.size = size
        self.initials = AuthorMonogram.initials(name: name, email: colorSeed ?? "")
        let lanes = Self.colors
        self.background = lanes[AuthorMonogram.paletteIndex(seed: colorSeed ?? name, count: lanes.count)]
    }

    /// Avatar backgrounds; fixed so an author keeps their colour.
    static let colors: [Color] = [
        Color(hex: 0x7c5cff),
        Color(hex: 0xff7e6b),
        Color(hex: 0x56b497),
        Color(hex: 0xdda44b),
        Color(hex: 0x5da4ff),
        Color(hex: 0xc976d9),
    ]

    /// Stable palette slot for `seed` (`AuthorMonogram.paletteIndex`).
    static func paletteIndex(seed: String, count: Int) -> Int {
        AuthorMonogram.paletteIndex(seed: seed, count: count)
    }

    static func paletteIndex(hash: Int, count: Int) -> Int {
        AuthorMonogram.paletteIndex(hash: hash, count: count)
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
