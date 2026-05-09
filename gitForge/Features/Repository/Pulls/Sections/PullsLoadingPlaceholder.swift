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
            LazyVStack(spacing: DesignTokens.Spacing.md) {
                ForEach(0..<6, id: \.self) { index in
                    row(index: index)
                }
            }
            .padding(DesignTokens.Spacing.xxxxl)
        }
        .skeleton(true)
    }

    private func row(index: Int) -> some View {
        let title = Self.titles[index % Self.titles.count]
        let branch = Self.branches[index % Self.branches.count]

        return HStack(spacing: DesignTokens.Spacing.xl) {
            PullRequestStatePill(state: .open)
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                HStack(spacing: DesignTokens.Spacing.md) {
                    Text(title)
                        .font(AppFont.sans(13, weight: .medium))
                        .foregroundStyle(theme.palette.fg1)
                        .lineLimit(1)
                    MonoText("#000", dim: true)
                }
                HStack(spacing: DesignTokens.Spacing.sm) {
                    MonoText("@author", dim: true)
                    Text("·").foregroundStyle(theme.palette.fg4)
                    MonoText(branch, dim: true)
                    Text("→").foregroundStyle(theme.palette.fg4)
                    MonoText("main", dim: true)
                    Text("·").foregroundStyle(theme.palette.fg4)
                    MonoText("2h ago", dim: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, DesignTokens.Spacing.xxl)
        .padding(.vertical, DesignTokens.Spacing.lg)
        .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).fill(theme.palette.bg1))
        .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).stroke(theme.palette.line, lineWidth: DesignTokens.Stroke.regular))
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    PullsLoadingPlaceholder()
        .frame(width: 1100, height: 600)
        .background(theme.palette.bg2)
        .appTheme(theme)
}
