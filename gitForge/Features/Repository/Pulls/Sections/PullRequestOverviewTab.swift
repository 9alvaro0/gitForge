import SwiftUI

/// Banner, mergeability (with "Resolve locally" when it conflicts) and the
/// description. Reviewers and labels live in the header.
struct PullRequestOverviewTab: View {
    let detail: PullRequestDetail?
    var banner: AnyView = AnyView(EmptyView())
    var localMergeRunning: Bool = false
    var onTryLocalMerge: () -> Void = {}

    @Environment(\.appTheme) private var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s16) {
                banner
                if let detail {
                    if detail.mergeable == false {
                        conflictsCard
                    }
                    descriptionCard(detail)
                } else {
                    descriptionPlaceholder.skeleton(true)
                }
            }
            .padding(Spacing.s24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var conflictsCard: some View {
        HStack(spacing: Spacing.s12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(theme.colors.warn)
            Text("This branch conflicts with its target. Merge the target into it locally and resolve the conflicts here.")
                .textRole(.callout)
                .foregroundStyle(theme.colors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            GFButton(title: localMergeRunning ? "Resolving…" : "Resolve locally", disabled: localMergeRunning,
                     action: onTryLocalMerge)
        }
        .padding(Spacing.s12)
        .background(RoundedRectangle(cornerRadius: Radius.card).fill(theme.colors.bgContent))
        .overlay(RoundedRectangle(cornerRadius: Radius.card).strokeBorder(theme.colors.separator, lineWidth: 1))
    }

    private func descriptionCard(_ detail: PullRequestDetail) -> some View {
        card {
            OverviewSectionLabel("Description")
            if let body = detail.descriptionMarkdown, !body.isEmpty {
                MarkdownView(source: body)
            } else {
                Text("No description provided.")
                    .textRole(.body)
                    .foregroundStyle(theme.colors.textTertiary)
            }
        }
    }

    private var descriptionPlaceholder: some View {
        card {
            OverviewSectionLabel("Description")
            Text("Adds the PR/MR integration with the new detail view, including overview, commits, and files tabs.")
                .textRole(.body)
            Text("Each tab shares state with the parent so navigating between them is instantaneous.")
                .textRole(.body)
        }
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s8) {
            content()
        }
        .padding(Spacing.s16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.card).fill(theme.colors.bgContent))
        .overlay(RoundedRectangle(cornerRadius: Radius.card).strokeBorder(theme.colors.separator, lineWidth: 1))
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    PullRequestOverviewTab(detail: .previewSample)
        .frame(width: 800, height: 600)
        .background(theme.colors.bgElevated)
        .appTheme(theme)
}
