import SwiftUI
import AppKit

/// Right-side commit detail in the History view.
struct CommitDetailColumn: View {
    let commit: Commit
    @Bindable var viewModel: RepositoryViewModel
    /// Optional handler for the close icon at the panel top. When `nil` the
    /// button is hidden — used by History to collapse the panel.
    var onClose: (() -> Void)? = nil

    @Environment(\.appTheme) private var theme

    private var detail: CommitDetail? { viewModel.detailCache[commit.sha] }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxl) {
            shaLine
            Text(commit.subject)
                .font(AppFont.sans(14))
                .foregroundStyle(theme.palette.fg1)
            CommitMetaCard(commit: commit)
            if let detail, !detail.bodyText.isEmpty {
                Text(detail.bodyText)
                    .font(AppFont.mono(12, family: theme.monoFont))
                    .foregroundStyle(theme.palette.fg2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            CommitFilesSection(commit: commit, viewModel: viewModel)
            CommitActionsSection(commit: commit, viewModel: viewModel)
        }
        .task(id: commit.sha) {
            _ = await viewModel.detail(for: commit)
        }
    }

    private var shaLine: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            GFIcon(kind: .diamond, size: 14, stroke: theme.palette.fg1)
            Text(commit.shortSha)
                .font(AppFont.mono(13, family: theme.monoFont))
                .foregroundStyle(theme.palette.fg1)
            IconButton(.copy, accessibilityLabel: "Copy full SHA") {
                NSPasteboard.general.declareTypes([.string], owner: nil)
                NSPasteboard.general.setString(commit.sha, forType: .string)
            }
            .help("Copy full SHA")
            Spacer()
            if let onClose {
                IconButton(.x, accessibilityLabel: "Hide commit detail", action: onClose)
                    .help("Hide commit detail")
            }
        }
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    CommitDetailColumn(commit: .preview, viewModel: .preview)
        .previewAppState(.preview)
        .padding()
        .frame(width: DesignTokens.Detail.panelWidth, height: 720)
        .background(theme.palette.bg1)
        .appTheme(theme)
}
