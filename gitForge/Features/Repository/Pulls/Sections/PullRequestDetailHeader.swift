import SwiftUI

struct PullRequestDetailHeader: View {
    let pullRequest: PullRequest
    let onBack: () -> Void

    @Environment(\.appTheme) private var theme
    @Environment(\.appPreferences) private var preferences

    var body: some View {
        DetailHeader(onBack: onBack) {
            if let url = pullRequest.webURL {
                ToolButton(.ext, label: "Open in browser") {
                    ExternalURL.open(url)
                }
            }
        } content: {
            HStack(alignment: .firstTextBaseline, spacing: DesignTokens.Spacing.md) {
                PullRequestStatePill(state: pullRequest.state)
                Text(pullRequest.title)
                    .font(AppFont.sans(DesignTokens.Detail.titleFontSize, weight: .semibold))
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
                    MonoText(preferences.dateDisplayMode.format(updated), dim: true)
                }
            }
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
