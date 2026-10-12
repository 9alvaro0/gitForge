import SwiftUI

/// `.gf-mono` — monospace text with theme-aware font, dim variant.
struct MonoText: View {
    let text: String
    var size: CGFloat?
    var weight: Font.Weight = .regular
    var dim: Bool = false
    var color: Color?

    @Environment(\.appTheme) private var theme

    init(_ text: String, size: CGFloat? = nil, weight: Font.Weight = .regular, dim: Bool = false, color: Color? = nil) {
        self.text = text
        self.size = size
        self.weight = weight
        self.dim = dim
        self.color = color
    }

    /// The requested size (or the density's mono size) snaps to the nearest
    /// mono role.
    private var font: Font {
        let target = size ?? theme.density.monoFontSize
        let role: TypeRole = target >= (TypeRole.mono.size + TypeRole.monoSmall.size) / 2 ? .mono : .monoSmall
        return AppFont.font(role, weight: weight, monoFamily: theme.monoFont)
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
