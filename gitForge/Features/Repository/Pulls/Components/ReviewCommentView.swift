import SwiftUI

/// One comment of a review thread: who, when, and the body as markdown.
struct ReviewCommentView: View {
    let comment: ReviewComment

    @Environment(\.appTheme) private var theme
    @Environment(\.appPreferences) private var preferences

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.s8) {
            Avatar(name: author, size: 20, colorSeed: author)
            VStack(alignment: .leading, spacing: Spacing.s4) {
                HStack(spacing: Spacing.s6) {
                    Text(author)
                        .textRole(.callout, weight: .semibold)
                        .foregroundStyle(theme.colors.textPrimary)
                    if let created = comment.createdAt {
                        Text(preferences.dateDisplayMode.format(created))
                            .textRole(.caption)
                            .foregroundStyle(theme.colors.textTertiary)
                    }
                }
                .lineLimit(1)
                MarkdownView(source: comment.body)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// GitHub shows a deleted account as "ghost".
    private var author: String { comment.authorLogin ?? "ghost" }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    ReviewCommentView(comment: ReviewThread.previewOpen.comments[0])
        .padding()
        .frame(width: 520)
        .background(theme.colors.bgElevated)
        .appTheme(theme)
}
