import SwiftUI

struct StashFilesTab: View {
    let store: StashDetailStore
    @Binding var diffMode: DiffPane.ViewMode

    @Environment(\.appTheme) private var theme

    private var files: [StashFileChange] { store.detail?.files ?? [] }

    /// Fits the files up to about seven rows, then scrolls.
    private var fileListHeight: CGFloat {
        let rows = CGFloat(min(files.count, 7))
        return rows * theme.density.metrics.rowFile + Spacing.s6 * 2
    }

    var body: some View {
        if files.isEmpty {
            if store.isLoading {
                placeholderList
            } else {
                EmptyState(icon: .diff, title: "No files changed")
            }
        } else {
            // Files over the diff, as in the commit inspector: side by side
            // the diff would get too narrow next to the stash list.
            VStack(spacing: 0) {
                fileList
                    .frame(height: fileListHeight)
                Rectangle().fill(theme.colors.separator).frame(height: 1)
                DiffPane(
                    file: store.selectedFile,
                    status: files.first { $0.path == store.selectedFile }.map { StatusTag.Kind(stashFile: $0.status) },
                    hunks: store.fileDiff,
                    loading: store.isLoadingFileDiff,
                    emptyState: store.fileDiffEmptyState,
                    viewMode: $diffMode
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var fileList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(files) { file in
                    StashFileRow(
                        file: file,
                        isSelected: file.path == store.selectedFile,
                        onSelect: { Task { await store.loadFileDiff(at: file.path) } }
                    )
                }
            }
            .padding(Spacing.s6)
        }
    }

    private var placeholderList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(StashFileChange.previewSamples) { file in
                    StashFileRow(file: file, isSelected: false, onSelect: {})
                }
            }
            .padding(Spacing.s6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .skeleton(true)
    }
}

#Preview("Loaded") {
    @Previewable @State var theme = AppTheme()
    @Previewable @State var mode: DiffPane.ViewMode = .unified
    StashFilesTab(store: RepositoryViewModel.previewWithStashDetail.stashDetail, diffMode: $mode)
        .frame(width: 1200, height: 720)
        .background(theme.colors.bgContent)
        .appTheme(theme)
}

#Preview("Loading") {
    @Previewable @State var theme = AppTheme()
    @Previewable @State var mode: DiffPane.ViewMode = .unified
    let vm: RepositoryViewModel = {
        let v = RepositoryViewModel.previewWithStashes
        v.stashDetail.selected = Stash.previewSamples.first
        v.stashDetail.isLoading = true
        return v
    }()
    StashFilesTab(store: vm.stashDetail, diffMode: $mode)
        .frame(width: 1200, height: 720)
        .background(theme.colors.bgContent)
        .appTheme(theme)
}
