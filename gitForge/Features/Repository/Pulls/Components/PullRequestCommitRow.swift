import SwiftUI

struct PullRequestCommitRow: View {
    let commit: PullRequestCommit
    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.xl) {
            MonoText(commit.shortSha, color: theme.palette.accent)
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                Text(commit.subject)
                    .font(AppFont.sans(12.5))
                    .foregroundStyle(theme.palette.fg1)
                    .lineLimit(1)
                    .truncationMode(.tail)
                HStack(spacing: DesignTokens.Spacing.sm) {
                    if let author = commit.authorName {
                        MonoText(author, dim: true)
                    }
                    if let date = commit.authorDate {
                        Text("·").foregroundStyle(theme.palette.fg4)
                        MonoText(theme.dateDisplayMode.format(date), dim: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, DesignTokens.Spacing.xl)
        .padding(.vertical, DesignTokens.Spacing.md)
        .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).fill(theme.palette.bg1))
        .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).stroke(theme.palette.line, lineWidth: DesignTokens.Stroke.regular))
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    VStack(spacing: 8) {
        PullRequestCommitRow(commit: PullRequestCommit(
            sha: "abc1234abcdef", subject: "feat: add PR detail view",
            authorName: "9alvaro0", authorDate: Date(timeIntervalSinceNow: -3600)
        ))
        PullRequestCommitRow(commit: PullRequestCommit(
            sha: "def5678abcdef", subject: "refactor: split provider",
            authorName: "9alvaro0", authorDate: Date(timeIntervalSinceNow: -7200)
        ))
    }
    .padding()
    .frame(width: 720)
    .background(theme.palette.bg2)
    .appTheme(theme)
}
