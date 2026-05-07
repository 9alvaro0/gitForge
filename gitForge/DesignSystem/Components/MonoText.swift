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

    var body: some View {
        Text(text)
            .font(AppFont.mono(size ?? theme.density.monoFontSize, weight: weight, family: theme.monoFont))
            .foregroundStyle(color ?? (dim ? theme.palette.fg3 : theme.palette.fg2))
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    VStack(alignment: .leading, spacing: 6) {
        MonoText("a4f3c12 · feat/commit-graph")
        MonoText("just now", dim: true)
        MonoText("12.5px", weight: .semibold, color: theme.palette.accent)
    }
    .padding(20)
    .background(theme.palette.bg2)
    .appTheme(theme)
}
