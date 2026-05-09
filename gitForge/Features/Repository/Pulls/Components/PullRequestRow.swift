import SwiftUI
import AppKit

struct PullRequestRow: View {
    let pullRequest: PullRequest
    let onSelect: () -> Void

    @Environment(\.appTheme) private var theme

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: DesignTokens.Spacing.xl) {
                PullRequestStatePill(state: pullRequest.state)
                metadata
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let webURL = pullRequest.webURL {
                    openButton(url: webURL)
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.xxl)
            .padding(.vertical, DesignTokens.Spacing.lg)
            .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).fill(theme.palette.bg1))
            .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).stroke(theme.palette.line, lineWidth: DesignTokens.Stroke.regular))
            .contentShape(.rect(cornerRadius: DesignTokens.Radius.md))
        }
        .buttonStyle(.plain)
    }

    private var metadata: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            HStack(spacing: DesignTokens.Spacing.md) {
                Text(pullRequest.title)
                    .font(AppFont.sans(13, weight: .medium))
                    .foregroundStyle(theme.palette.fg1)
                    .lineLimit(1)
                    .truncationMode(.tail)
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
    }

    private func openButton(url: URL) -> some View {
        Button {
            NSWorkspace.shared.open(url)
        } label: {
            Text("Open")
                .font(AppFont.sans(11))
                .foregroundStyle(theme.palette.fg2)
                .padding(.horizontal, DesignTokens.Spacing.md)
                .frame(height: 22)
                .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.xs).fill(theme.palette.bg2))
                .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.xs).stroke(theme.palette.line, lineWidth: DesignTokens.Stroke.regular))
                .contentShape(.rect(cornerRadius: DesignTokens.Radius.xs))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    VStack(spacing: 8) {
        ForEach(PullRequest.previewSamples) { pr in
            PullRequestRow(pullRequest: pr, onSelect: {})
        }
    }
    .padding()
    .frame(width: 760)
    .background(theme.palette.bg2)
    .appTheme(theme)
}
