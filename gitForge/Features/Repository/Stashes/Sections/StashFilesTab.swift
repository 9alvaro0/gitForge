import SwiftUI

struct StashFilesTab: View {
    let store: StashDetailStore
    @Binding var diffMode: DiffPane.ViewMode

    @Environment(\.appTheme) private var theme

    private var files: [StashFileChange] { store.detail?.files ?? [] }

    var body: some View {
        if files.isEmpty {
            if store.isLoading {
                placeholderList
            } else {
                EmptyState(icon: .diff, title: "No files changed", subtitle: nil) { EmptyView() }
            }
        } else {
            HStack(spacing: DesignTokens.Spacing.none) {
                fileList
                    .frame(width: DesignTokens.Pulls.listWidth)
                    .frame(maxHeight: .infinity)
                    .background(theme.palette.bg1)
                    .overlay(alignment: .trailing) {
                        Rectangle().fill(theme.palette.line).frame(width: DesignTokens.Stroke.regular)
                    }
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
            LazyVStack(spacing: DesignTokens.Spacing.none) {
                ForEach(files) { file in
                    StashFileRow(
                        file: file,
                        isSelected: file.path == store.selectedFile,
                        onSelect: { Task { await store.loadFileDiff(at: file.path) } }
                    )
                }
            }
        }
    }

    private var placeholderList: some View {
        ScrollView {
            LazyVStack(spacing: DesignTokens.Spacing.none) {
                ForEach(StashFileChange.previewSamples) { file in
                    StashFileRow(file: file, isSelected: false, onSelect: {})
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.palette.bg1)
        .skeleton(true)
    }
}

#Preview("Loaded") {
    @Previewable @State var theme = AppTheme()
    @Previewable @State var mode: DiffPane.ViewMode = .unified
    StashFilesTab(store: RepositoryViewModel.previewWithStashDetail.stashDetail, diffMode: $mode)
        .frame(width: 1200, height: 720)
        .background(theme.palette.bg2)
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
        .background(theme.palette.bg2)
        .appTheme(theme)
}
