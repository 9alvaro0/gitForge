import SwiftUI

/// Skeleton list shown while the first PR/MR fetch is in flight. Sample
/// titles/branches keep the layout realistic so the user perceives loading,
/// not a blank state.
struct PullsLoadingPlaceholder: View {
    @Environment(\.appTheme) private var theme

    private static let titles = [
        "Add merge request integration",
        "Resizable diff pane and toolbar pinning",
        "WIP: graph perf experiments",
        "Refactor sidebar redesigned layout",
        "Pull request detail view header",
        "Improve fetch performance and retries",
    ]

    private static let branches = [
        "feat/mr-integration",
        "feat/diff-pane",
        "feat/graph-perf",
        "feat/sidebar",
        "feat/pr-detail",
        "feat/fetch-perf",
    ]

    var body: some View {
        ScrollView {
            LazyVStack(spacing: Spacing.s2) {
                ForEach(0..<6, id: \.self) { index in
                    PullRequestRow(
                        pullRequest: PullRequest(
                            id: "\(index)", number: 200 + index, title: Self.titles[index % Self.titles.count],
                            state: .open, authorLogin: "author", authorAvatarURL: nil,
                            sourceBranch: Self.branches[index % Self.branches.count], targetBranch: "main",
                            webURL: nil, createdAt: nil, updatedAt: nil),
                        hostLabel: "GitHub", ci: nil, isSelected: false, onSelect: {})
                }
            }
            .padding(Spacing.s8)
        }
        .skeleton(true)
        .allowsHitTesting(false)
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    PullsLoadingPlaceholder()
        .frame(width: 1100, height: 600)
        .background(theme.colors.bgContent)
        .appTheme(theme)
}
