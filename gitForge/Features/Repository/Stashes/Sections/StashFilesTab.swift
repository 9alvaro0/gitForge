import SwiftUI

struct StashFilesTab: View {
    @Bindable var viewModel: RepositoryViewModel
    @Binding var diffMode: DiffPane.ViewMode

    @Environment(\.appTheme) private var theme

    private var files: [StashFileChange] { viewModel.stashDetail?.files ?? [] }

    var body: some View {
        if files.isEmpty {
            if viewModel.stashDetailLoading {
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
                    file: viewModel.selectedStashFile,
                    hunks: viewModel.stashFileDiff,
                    loading: viewModel.loadingStashFileDiff,
                    emptyState: viewModel.stashFileDiffEmptyState,
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
                        isSelected: file.path == viewModel.selectedStashFile,
                        onSelect: { Task { await viewModel.loadStashFileDiff(at: file.path) } }
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
    StashFilesTab(viewModel: .previewWithStashDetail, diffMode: $mode)
        .frame(width: 1200, height: 720)
        .background(theme.palette.bg2)
        .appTheme(theme)
}

#Preview("Loading") {
    @Previewable @State var theme = AppTheme()
    @Previewable @State var mode: DiffPane.ViewMode = .unified
    let vm: RepositoryViewModel = {
        let v = RepositoryViewModel.previewWithStashes
        v.selectedStash = Stash.previewSamples.first
        v.stashDetailLoading = true
        return v
    }()
    StashFilesTab(viewModel: vm, diffMode: $mode)
        .frame(width: 1200, height: 720)
        .background(theme.palette.bg2)
        .appTheme(theme)
}
