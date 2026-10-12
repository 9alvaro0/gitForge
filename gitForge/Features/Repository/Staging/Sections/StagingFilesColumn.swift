import SwiftUI

/// Unstaged above Staged, each with its select-all header, rows and — while
/// some of its files are ticked — the batch bar.
struct StagingFilesColumn: View {
    @Bindable var viewModel: RepositoryViewModel
    let staged: [WorkingCopyFile]
    let unstaged: [WorkingCopyFile]
    let statusLoading: Bool
    /// The toolbar filter is hiding files: empty sections say "No matches".
    var isFiltering = false

    @Environment(\.appTheme) private var theme

    var body: some View {
        ScrollView {
            Group {
                if statusLoading && staged.isEmpty && unstaged.isEmpty {
                    StagingLoadingPlaceholder()
                } else {
                    fileList
                }
            }
            .padding(Spacing.s8)
        }
    }

    private var fileList: some View {
        LazyVStack(spacing: 0) {
            section(
                title: "Unstaged",
                files: unstaged,
                emptyText: isFiltering ? "No matches" : "No unstaged changes",
                allLabel: "Stage all",
                onAll: { Task { await viewModel.stage(unstaged) } },
                moveTitle: "Stage",
                onMove: { Task { await viewModel.stageSelected() } }
            )
            section(
                title: "Staged",
                files: staged,
                emptyText: isFiltering ? "No matches" : "Nothing staged",
                allLabel: "Unstage all",
                onAll: { Task { await viewModel.unstage(staged) } },
                moveTitle: "Unstage",
                onMove: { Task { await viewModel.unstageSelected() } }
            )
            .padding(.top, Spacing.s12)
        }
    }

    @ViewBuilder
    private func section(title: String,
                         files: [WorkingCopyFile],
                         emptyText: String,
                         allLabel: String,
                         onAll: @escaping () -> Void,
                         moveTitle: String,
                         onMove: @escaping () -> Void) -> some View {
        let selection = StagingSectionSelection(paths: files.map(\.path), selected: viewModel.workingCopy.selectedFilePaths)
        VStack(spacing: 0) {
            StagingFileSectionHeader(
                title: title,
                count: files.count,
                selection: selection,
                onToggleAll: { viewModel.workingCopy.setSelection(files, selected: selection != .full) },
                actionLabel: allLabel,
                onAction: onAll
            )
            if files.isEmpty {
                Text(emptyText)
                    .textRole(.callout)
                    .foregroundStyle(theme.colors.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Spacing.s8)
                    .frame(height: theme.density.metrics.rowList)
            } else {
                ForEach(files) { f in
                    StagingRow(file: f, viewModel: viewModel)
                }
            }
            if selection != .empty {
                StagingBatchBar(
                    count: selection.count(of: files.count),
                    moveTitle: moveTitle,
                    onMove: onMove,
                    onStash: {
                        let ticked = files.filter { viewModel.workingCopy.selectedFilePaths.contains($0.path) }
                        Task {
                            if await viewModel.stash(ticked) {
                                viewModel.workingCopy.deselect(ticked)
                            }
                        }
                    },
                    onDiscard: {
                        let ticked = files.filter { viewModel.workingCopy.selectedFilePaths.contains($0.path) }
                        Task {
                            await viewModel.discardChanges(ticked)
                            viewModel.workingCopy.deselect(ticked)
                        }
                    },
                    disabled: viewModel.isMutating
                )
            }
        }
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    let vm: RepositoryViewModel = .preview
    StagingFilesColumn(
        viewModel: vm,
        staged: vm.workingCopy.status.stagedFiles,
        unstaged: vm.workingCopy.status.unstagedFiles,
        statusLoading: false
    )
    .frame(width: 440, height: 600)
    .background(theme.colors.bgContent)
    .appTheme(theme)
}
