import SwiftUI

struct PullRequestCommitRow: View {
    let commit: PullRequestCommit
    @Environment(\.appTheme) private var theme
    @Environment(\.appPreferences) private var preferences

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.s12) {
            Text(commit.shortSha)
                .font(AppFont.font(.monoSmall, monoFamily: theme.monoFont))
                .foregroundStyle(theme.colors.accent)
                .textSelection(.enabled)
            VStack(alignment: .leading, spacing: Spacing.s2) {
                Text(commit.subject)
                    .textRole(.body)
                    .foregroundStyle(theme.colors.textPrimary)
                    .lineLimit(2)
                HStack(spacing: Spacing.s6) {
                    if let author = commit.authorName {
                        Text(author)
                    }
                    if let date = commit.authorDate {
                        Text("·")
                        Text(preferences.dateDisplayMode.format(date))
                    }
                }
                .textRole(.callout)
                .foregroundStyle(theme.colors.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, Spacing.s12)
        .padding(.vertical, Spacing.s8)
        .background(RoundedRectangle(cornerRadius: Radius.control).fill(theme.colors.bgContent))
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    VStack(spacing: 8) {
        ForEach(PullRequestCommit.previewSamples.prefix(3)) { commit in
            PullRequestCommitRow(commit: commit)
        }
    }
    .padding()
    .frame(width: 720)
    .background(theme.colors.bgElevated)
    .appTheme(theme)
}
