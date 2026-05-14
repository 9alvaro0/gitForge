import SwiftUI
import AppKit

/// Right-side detail panel shown in the History view when the user selects
/// the pinned "Uncommitted changes" row. Lists the working-copy files and
/// drives `viewModel.selectedWorkingCopyFile`, which the bottom diff pane
/// already consumes — so click-to-diff lights up automatically without a
/// parallel selection model.
struct UncommittedDetailColumn: View {
    @Bindable var viewModel: RepositoryViewModel
    /// Optional close handler so the host can collapse the panel. Matches the
    /// `CommitDetailColumn` contract for the shared `HistoryView` layout.
    var onClose: (() -> Void)? = nil

    @Environment(\.appTheme) private var theme

    private var staged: [WorkingCopyFile]   { viewModel.status.stagedFiles }
    private var unstaged: [WorkingCopyFile] { viewModel.status.unstagedFiles }
    private var totalCount: Int { staged.count + unstaged.count }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxl) {
            header
            Text("Working tree changes not yet committed.")
                .font(AppFont.sans(12.5))
                .foregroundStyle(theme.palette.fg3)
            if totalCount == 0 {
                Text("No changes")
                    .font(AppFont.sans(12))
                    .italic()
                    .foregroundStyle(theme.palette.fg3)
            } else {
                fileSection(title: "STAGED", count: staged.count, files: staged)
                fileSection(title: "UNSTAGED", count: unstaged.count, files: unstaged)
            }
        }
    }

    private var header: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            GFIcon(kind: .diff, size: 14, stroke: theme.palette.fg1)
            Text("Uncommitted changes")
                .font(AppFont.sans(13))
                .foregroundStyle(theme.palette.fg1)
            Spacer()
            if let onClose {
                IconButton(.x, accessibilityLabel: "Hide uncommitted detail", action: onClose)
                    .help("Hide uncommitted detail")
            }
        }
    }

    @ViewBuilder
    private func fileSection(title: String, count: Int, files: [WorkingCopyFile]) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            HStack {
                Text(title)
                    .font(.system(size: FontSize.footnote, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(theme.palette.fg3)
                Text("\(count)")
                    .font(.system(size: FontSize.footnote))
                    .foregroundStyle(theme.palette.fg3)
            }
            if files.isEmpty {
                Text("Nothing \(title.lowercased())")
                    .font(AppFont.sans(12))
                    .italic()
                    .foregroundStyle(theme.palette.fg3)
            } else {
                LazyVStack(spacing: DesignTokens.Spacing.hairline) {
                    ForEach(files) { file in
                        WorkingCopyMiniRow(
                            file: file,
                            absoluteURL: viewModel.repository.url.appendingPathComponent(file.path),
                            isActive: viewModel.selectedWorkingCopyFile?.id == file.id
                        ) {
                            viewModel.selectedWorkingCopyFile = file
                        }
                    }
                }
            }
        }
    }
}

private struct WorkingCopyMiniRow: View {
    let file: WorkingCopyFile
    let absoluteURL: URL
    let isActive: Bool
    let onSelect: () -> Void

    @Environment(\.appTheme) private var theme

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: DesignTokens.Spacing.md) {
                StatusTag(kind: StatusTag.Kind(workingFile: file.isStaged ? file.stagedStatus : file.unstagedStatus))
                Text(file.path)
                    .font(AppFont.mono(11.5, family: theme.monoFont))
                    .foregroundStyle(theme.palette.fg1)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, DesignTokens.Spacing.md)
            .padding(.vertical, DesignTokens.Spacing.sm)
            .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm).fill(isActive ? theme.palette.bg3 : .clear))
            .contentShape(.rect(cornerRadius: DesignTokens.Radius.sm))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Open in editor") {
                NSWorkspace.shared.open(absoluteURL)
            }
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([absoluteURL])
            }
            Divider()
            Button("Copy path") { copyToPasteboard(file.path) }
            Button("Copy filename") { copyToPasteboard((file.path as NSString).lastPathComponent) }
        }
    }

    private func copyToPasteboard(_ string: String) {
        NSPasteboard.general.declareTypes([.string], owner: nil)
        NSPasteboard.general.setString(string, forType: .string)
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    UncommittedDetailColumn(viewModel: .preview)
        .previewAppState(.preview)
        .padding()
        .frame(width: DesignTokens.Detail.panelWidth, height: 720)
        .background(theme.palette.bg1)
        .appTheme(theme)
}
