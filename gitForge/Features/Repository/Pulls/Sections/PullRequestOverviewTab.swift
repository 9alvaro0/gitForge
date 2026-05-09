import SwiftUI

struct PullRequestOverviewTab: View {
    let detail: PullRequestDetail?
    var localMergeRunning: Bool = false
    var onTryLocalMerge: () -> Void = {}

    @Environment(\.appTheme) private var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxxl) {
                if let detail {
                    metaRow(detail)
                    descriptionBlock(detail)
                    if !detail.reviewers.isEmpty { reviewersBlock(detail) }
                    if !detail.labels.isEmpty { labelsBlock(detail) }
                } else {
                    placeholderContent
                        .skeleton(true)
                }
            }
            .padding(DesignTokens.Spacing.xxxxl)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private var placeholderContent: some View {
        FlowLayout(spacing: DesignTokens.Spacing.md) {
            Text("CI: All checks passed")
                .font(AppFont.sans(11))
                .padding(.horizontal, DesignTokens.Spacing.sm).padding(.vertical, DesignTokens.Spacing.xxs)
                .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.xs).fill(theme.palette.bg3))
            Text("Mergeable")
                .font(AppFont.sans(11))
                .padding(.horizontal, DesignTokens.Spacing.sm).padding(.vertical, DesignTokens.Spacing.xxs)
                .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.xs).fill(theme.palette.bg3))
        }

        block {
            OverviewSectionLabel("Description")
            Text("Adds the PR/MR integration with the new detail view, including overview, commits, and files tabs.")
                .font(AppFont.sans(12))
                .foregroundStyle(theme.palette.fg2)
            Text("Each tab shares state with the parent so navigating between them is instantaneous.")
                .font(AppFont.sans(12))
                .foregroundStyle(theme.palette.fg2)
        }

        block {
            OverviewSectionLabel("Reviewers")
            FlowLayout(spacing: DesignTokens.Spacing.sm) {
                ForEach(["@reviewer-one", "@reviewer-two", "@reviewer-three"], id: \.self) { name in
                    MonoText(name)
                        .padding(.horizontal, DesignTokens.Spacing.sm).padding(.vertical, DesignTokens.Spacing.xxs)
                        .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.xs).fill(theme.palette.bg2))
                }
            }
        }

        block {
            OverviewSectionLabel("Labels")
            FlowLayout(spacing: DesignTokens.Spacing.sm) {
                ForEach(["feature", "phase-2", "needs-review"], id: \.self) { name in
                    Text(name)
                        .font(AppFont.sans(11))
                        .padding(.horizontal, DesignTokens.Spacing.sm).padding(.vertical, DesignTokens.Spacing.xxs)
                        .foregroundStyle(theme.palette.fg2)
                        .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.xs).fill(theme.palette.bg2))
                }
            }
        }
    }

    @ViewBuilder
    private func metaRow(_ detail: PullRequestDetail) -> some View {
        FlowLayout(spacing: DesignTokens.Spacing.md) {
            if let ci = detail.ciStatus {
                CIPill(ci: ci)
            }
            MergeabilityPill(mergeable: detail.mergeable)
            if detail.mergeable == false {
                GFButton(
                    title: localMergeRunning ? "Resolving…" : "Resolve locally",
                    size: .small,
                    disabled: localMergeRunning
                ) {
                    onTryLocalMerge()
                }
            }
        }
    }

    @ViewBuilder
    private func descriptionBlock(_ detail: PullRequestDetail) -> some View {
        block {
            OverviewSectionLabel("Description")
            if let body = detail.descriptionMarkdown, !body.isEmpty {
                MarkdownView(source: body)
            } else {
                Text("No description provided.")
                    .font(AppFont.sans(12))
                    .foregroundStyle(theme.palette.fg3)
            }
        }
    }

    @ViewBuilder
    private func reviewersBlock(_ detail: PullRequestDetail) -> some View {
        block(spacing: DesignTokens.Spacing.sm) {
            OverviewSectionLabel("Reviewers")
            FlowLayout(spacing: DesignTokens.Spacing.sm) {
                ForEach(detail.reviewers) { r in
                    HStack(spacing: DesignTokens.Spacing.xs) {
                        if r.approved {
                            Text("✓")
                                .font(AppFont.mono(10, weight: .bold, family: theme.monoFont))
                                .foregroundStyle(theme.palette.ok)
                        }
                        MonoText("@\(r.login)")
                    }
                    .padding(.horizontal, DesignTokens.Spacing.sm)
                    .padding(.vertical, DesignTokens.Spacing.xxs)
                    .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.xs).fill(theme.palette.bg2))
                }
            }
        }
    }

    @ViewBuilder
    private func labelsBlock(_ detail: PullRequestDetail) -> some View {
        block(spacing: DesignTokens.Spacing.sm) {
            OverviewSectionLabel("Labels")
            FlowLayout(spacing: DesignTokens.Spacing.sm) {
                ForEach(detail.labels, id: \.self) { name in
                    Text(name)
                        .font(AppFont.sans(11))
                        .padding(.horizontal, DesignTokens.Spacing.sm)
                        .padding(.vertical, DesignTokens.Spacing.xxs)
                        .foregroundStyle(theme.palette.fg2)
                        .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.xs).fill(theme.palette.bg2))
                }
            }
        }
    }

    @ViewBuilder
    private func block<Content: View>(spacing: CGFloat = DesignTokens.Spacing.md,
                                      @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: spacing) {
            content()
        }
        .padding(DesignTokens.Spacing.xxl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).fill(theme.palette.bg1))
        .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).stroke(theme.palette.line, lineWidth: DesignTokens.Stroke.regular))
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    PullRequestOverviewTab(
        detail: PullRequestDetail(
            pull: PullRequest.previewSamples[0],
            descriptionMarkdown: "Adds the **PR/MR** integration with the detail view.",
            labels: ["feature", "phase-2"],
            reviewers: [.init(login: "reviewer1", approved: true), .init(login: "reviewer2", approved: false)],
            assignees: ["9alvaro0"],
            mergeable: true,
            ciStatus: CIStatus(state: .success, description: "All checks passed", webURL: nil)
        )
    )
    .frame(width: 1100, height: 700)
    .background(theme.palette.bg2)
    .appTheme(theme)
}
