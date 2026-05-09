import SwiftUI

struct ConflictLineRow: View {
    let lineNumber: Int
    let content: String
    let background: Color

    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.none) {
            Text("\(lineNumber)")
                .font(AppFont.mono(11, family: theme.monoFont))
                .foregroundStyle(theme.palette.fg4)
                .frame(width: 36, alignment: .trailing)
                .padding(.horizontal, DesignTokens.Spacing.md)
            Text(content.isEmpty ? " " : content)
                .font(AppFont.mono(theme.density.monoFontSize, family: theme.monoFont))
                .foregroundStyle(theme.palette.fg1)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.trailing, DesignTokens.Spacing.xxl)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background)
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    VStack(spacing: 0) {
        ConflictLineRow(lineNumber: 1, content: "let x = 42", background: theme.palette.addSoft)
        ConflictLineRow(lineNumber: 2, content: "let y = 99", background: theme.palette.addSoft)
        ConflictLineRow(lineNumber: 3, content: "", background: theme.palette.addSoft)
    }
    .frame(width: 480)
    .appTheme(theme)
}
