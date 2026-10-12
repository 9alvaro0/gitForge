import SwiftUI

/// `.gf-mono` — monospace text with theme-aware font, dim variant.
struct MonoText: View {
    let text: String
    var weight: Font.Weight = .regular
    var dim: Bool = false
    var color: Color?

    @Environment(\.appTheme) private var theme

    init(_ text: String, weight: Font.Weight = .regular, dim: Bool = false, color: Color? = nil) {
        self.text = text
        self.weight = weight
        self.dim = dim
        self.color = color
    }

    /// Mono role per density: 12 pt regular, 11 pt compact.
    static func role(for density: Density) -> TypeRole {
        density == .compact ? .monoSmall : .mono
    }

    private var font: Font {
        AppFont.font(Self.role(for: theme.density), weight: weight, monoFamily: theme.monoFont)
    }

    var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(color ?? (dim ? theme.colors.textTertiary : theme.colors.textSecondary))
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    VStack(alignment: .leading, spacing: Spacing.s6) {
        MonoText("a4f3c12 · feat/commit-graph")
        MonoText("just now", dim: true)
        MonoText("12.5px", weight: .semibold, color: theme.colors.accent)
    }
    .padding(Spacing.s20)
    .background(theme.colors.bgContent)
    .appTheme(theme)
}
