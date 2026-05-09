import SwiftUI

struct PullRequestCommitsTab: View {
    let commits: [PullRequestCommit]
    let loading: Bool

    @Environment(\.appTheme) private var theme

    var body: some View {
        if commits.isEmpty {
            if loading {
                placeholderList
            } else {
                EmptyState(icon: .graph, title: "No commits", subtitle: nil) { EmptyView() }
            }
        } else {
            ScrollView {
                LazyVStack(spacing: DesignTokens.Spacing.xs) {
                    ForEach(commits) { commit in
                        PullRequestCommitRow(commit: commit)
                    }
                }
                .padding(DesignTokens.Spacing.xxxxl)
            }
        }
    }

    private static let placeholderSamples: [PullRequestCommit] = [
        .init(sha: "abc1234abcdef", subject: "feat: add pull request detail view",
              authorName: "9alvaro0", authorDate: Date(timeIntervalSinceNow: -3600)),
        .init(sha: "def5678abcdef", subject: "refactor: split provider-specific mappers",
              authorName: "9alvaro0", authorDate: Date(timeIntervalSinceNow: -7200)),
        .init(sha: "fab9012abcdef", subject: "fix: handle nil reviewer avatar URLs",
              authorName: "9alvaro0", authorDate: Date(timeIntervalSinceNow: -10800)),
        .init(sha: "abc3456abcdef", subject: "chore: bump dependency versions",
              authorName: "9alvaro0", authorDate: Date(timeIntervalSinceNow: -14400)),
        .init(sha: "fed7890abcdef", subject: "test: cover empty merge request payloads",
              authorName: "9alvaro0", authorDate: Date(timeIntervalSinceNow: -18000)),
    ]

    private var placeholderList: some View {
        ScrollView {
            LazyVStack(spacing: DesignTokens.Spacing.xs) {
                ForEach(Self.placeholderSamples) { commit in
                    PullRequestCommitRow(commit: commit)
                }
            }
            .padding(DesignTokens.Spacing.xxxxl)
        }
        .skeleton(true)
    }
}

#Preview("Loaded") {
    @Previewable @State var theme = AppTheme()
    PullRequestCommitsTab(
        commits: [
            .init(sha: "abc1234abcdef", subject: "feat: add PR detail view", authorName: "9alvaro0", authorDate: Date(timeIntervalSinceNow: -3600)),
            .init(sha: "def5678abcdef", subject: "refactor: split provider", authorName: "9alvaro0", authorDate: Date(timeIntervalSinceNow: -7200)),
        ],
        loading: false
    )
    .frame(width: 1100, height: 600)
    .background(theme.palette.bg2)
    .appTheme(theme)
}

#Preview("Loading") {
    @Previewable @State var theme = AppTheme()
    PullRequestCommitsTab(commits: [], loading: true)
        .frame(width: 1100, height: 600)
        .background(theme.palette.bg2)
        .appTheme(theme)
}
