import SwiftUI
import AppKit

struct PullRequestDetailHeader: View {
    let pullRequest: PullRequest
    let onBack: () -> Void

    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            HStack(spacing: DesignTokens.Spacing.md) {
                GFButton(title: "← Back", size: .small, action: onBack)
                Spacer()
                if let url = pullRequest.webURL {
                    ToolButton(.ext, label: "Open in browser") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: DesignTokens.Spacing.md) {
                PullRequestStatePill(state: pullRequest.state)
                Text(pullRequest.title)
                    .font(AppFont.sans(16, weight: .semibold))
                    .foregroundStyle(theme.palette.fg1)
                    .lineLimit(2)
                MonoText("#\(pullRequest.number)", dim: true)
            }
            HStack(spacing: DesignTokens.Spacing.sm) {
                if let author = pullRequest.authorLogin {
                    MonoText("@\(author)", dim: true)
                    Text("·").foregroundStyle(theme.palette.fg4)
                }
                MonoText(pullRequest.sourceBranch, dim: true)
                Text("→").foregroundStyle(theme.palette.fg4)
                MonoText(pullRequest.targetBranch, dim: true)
                if let updated = pullRequest.updatedAt {
                    Text("·").foregroundStyle(theme.palette.fg4)
                    MonoText(theme.dateDisplayMode.format(updated), dim: true)
                }
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.xxxxl)
        .padding(.vertical, DesignTokens.Spacing.xxl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.palette.bg2)
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.palette.lineStrong).frame(height: DesignTokens.Stroke.regular)
        }
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    PullRequestDetailHeader(pullRequest: PullRequest.previewSamples[0], onBack: {})
        .frame(width: 1100)
        .background(theme.palette.bg2)
        .appTheme(theme)
}
