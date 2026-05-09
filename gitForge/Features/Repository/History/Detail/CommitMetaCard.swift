import SwiftUI

struct CommitMetaCard: View {
    let commit: Commit

    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.lg) {
            Avatar(name: commit.authorName, size: 20, colorSeed: commit.authorEmail)
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                Text(commit.authorName)
                    .font(AppFont.sans(12, weight: .medium))
                    .foregroundStyle(theme.palette.fg1)
                Text(commit.authorEmail)
                    .font(AppFont.mono(10.5, family: theme.monoFont))
                    .foregroundStyle(theme.palette.fg3)
            }
            Spacer()
            Text(theme.dateDisplayMode.format(commit.authorDate))
                .font(AppFont.mono(11, family: theme.monoFont))
                .foregroundStyle(theme.palette.fg3)
        }
        .padding(DesignTokens.Spacing.lg)
        .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).fill(theme.palette.bg2))
        .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).stroke(theme.palette.line, lineWidth: DesignTokens.Stroke.regular))
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    CommitMetaCard(commit: .preview)
        .padding()
        .frame(width: 380)
        .background(theme.palette.bg1)
        .appTheme(theme)
}
