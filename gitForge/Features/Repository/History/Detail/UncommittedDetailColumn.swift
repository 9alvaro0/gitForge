import SwiftUI
import AppKit

/// Right-side detail panel shown in the History view when the user selects
/// the pinned "Uncommitted changes" row. Lists the working-copy files and
/// drives `viewModel.workingCopy.selectedWorkingCopyFile`, which the bottom diff pane
/// already consumes — so click-to-diff lights up automatically without a
/// parallel selection model.
struct UncommittedDetailColumn: View {
    @Bindable var viewModel: RepositoryViewModel
    /// Optional close handler so the host can collapse the panel. Matches the
    /// `CommitDetailColumn` contract for the shared `HistoryView` layout.
    var onClose: (() -> Void)? = nil

    @Environment(\.appTheme) private var theme
    @FocusState private var listFocused: Bool

    private var staged: [WorkingCopyFile]   { viewModel.workingCopy.status.stagedFiles }
    private var unstaged: [WorkingCopyFile] { viewModel.workingCopy.status.unstagedFiles }
    private var totalCount: Int { staged.count + unstaged.count }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s12) {
            header
            Text("Working tree changes not yet committed.")
                .textRole(.body)
                .foregroundStyle(theme.colors.textTertiary)
            if totalCount == 0 {
                Text("No changes")
                    .textRole(.callout)
                    .italic()
                    .foregroundStyle(theme.colors.textTertiary)
            } else {
                // Inside the inspector's scroll view: the reader scrolls it.
                ScrollViewReader { proxy in
                    VStack(alignment: .leading, spacing: Spacing.s12) {
                        fileSection(title: "STAGED", count: staged.count, files: staged, side: .staged)
                        fileSection(title: "UNSTAGED", count: unstaged.count, files: unstaged, side: .unstaged)
                    }
                    .listKeyboardNavigation(
                        ids: rowIDs,
                        selection: viewModel.workingCopy.selectedRowID,
                        isFocused: $listFocused,
                        scrollProxy: proxy
                    ) { id in
                        viewModel.workingCopy.select(id, in: id.side == .staged ? staged : unstaged)
                    }
                }
            }
        }
    }

    /// Staged then Unstaged, the order ↑↓ walks them in.
    private var rowIDs: [WorkingCopyRowID] {
        staged.map { WorkingCopyRowID(side: .staged, path: $0.path) }
            + unstaged.map { WorkingCopyRowID(side: .unstaged, path: $0.path) }
    }

    private var header: some View {
        HStack(spacing: Spacing.s8) {
            SymbolGlyph("square.and.pencil", size: 14)
                .foregroundStyle(theme.colors.textPrimary)
            Text("Uncommitted changes")
                .textRole(.body)
                .foregroundStyle(theme.colors.textPrimary)
            Spacer()
            if let onClose {
                IconButton(symbol: "xmark", accessibilityLabel: "Hide uncommitted detail", action: onClose)
                    .help("Hide uncommitted detail")
            }
        }
    }

    @ViewBuilder
    private func fileSection(title: String, count: Int, files: [WorkingCopyFile], side: WorkingCopySide) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s8) {
            HStack {
                Text(title)
                    .textRole(.caption, weight: .semibold)
                    .tracking(0.8)
                    .foregroundStyle(theme.colors.textTertiary)
                Text("\(count)")
                    .textRole(.caption)
                    .foregroundStyle(theme.colors.textTertiary)
            }
            if files.isEmpty {
                Text("Nothing \(title.lowercased())")
                    .textRole(.callout)
                    .italic()
                    .foregroundStyle(theme.colors.textTertiary)
            } else {
                LazyVStack(spacing: 1) {
                    ForEach(files) { file in
                        WorkingCopyMiniRow(
                            file: file,
                            absoluteURL: viewModel.repository.url.appendingPathComponent(file.path),
                            isActive: viewModel.workingCopy.selectedWorkingCopyFile?.id == file.id
                                && viewModel.workingCopy.diffSide(for: file) == side
                        ) {
                            viewModel.workingCopy.select(file, side: side)
                            listFocused = true
                        }
                        .id(WorkingCopyRowID(side: side, path: file.path))
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
            HStack(spacing: Spacing.s8) {
                StatusTag(kind: StatusTag.Kind(workingFile: file.isStaged ? file.stagedStatus : file.unstagedStatus))
                Text(file.path)
                    .textRole(.mono)
                    .foregroundStyle(theme.colors.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, Spacing.s8)
            .padding(.vertical, Spacing.s6)
            .background(RoundedRectangle(cornerRadius: Radius.chip).fill(isActive ? theme.colors.fillControl : .clear))
            .contentShape(.rect(cornerRadius: Radius.chip))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Open in editor") {
                ExternalURL.openFile(absoluteURL)
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
        .frame(width: 360, height: 720)
        .background(theme.colors.bgElevated)
        .appTheme(theme)
}
