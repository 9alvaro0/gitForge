import SwiftUI

struct StagingFilesColumn: View {
    @Bindable var viewModel: RepositoryViewModel
    let staged: [WorkingCopyFile]
    let unstaged: [WorkingCopyFile]
    let statusLoading: Bool

    @Environment(\.appTheme) private var theme

    var body: some View {
        ScrollView {
            if statusLoading && staged.isEmpty && unstaged.isEmpty {
                StagingLoadingPlaceholder()
            } else {
                fileList
            }
        }
    }

    private var fileList: some View {
        LazyVStack(spacing: DesignTokens.Spacing.none) {
            StagingFileSectionHeader(
                title: "Staged",
                count: staged.count,
                actionLabel: "Unstage all"
            ) {
                Task { await viewModel.unstage(staged) }
            }
            if staged.isEmpty {
                emptyLabel("Nothing staged")
            } else {
                ForEach(staged) { f in
                    StagingRow(file: f, viewModel: viewModel)
                }
            }
            Divider().background(theme.palette.line)
            StagingFileSectionHeader(
                title: "Unstaged",
                count: unstaged.count,
                actionLabel: "Stage all"
            ) {
                Task { await viewModel.stage(unstaged) }
            }
            ForEach(unstaged) { f in
                StagingRow(file: f, viewModel: viewModel)
            }
        }
    }

    private func emptyLabel(_ text: String) -> some View {
        Text(text)
            .font(AppFont.sans(12))
            .foregroundStyle(theme.palette.fg3)
            .italic()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DesignTokens.Spacing.xxl)
            .padding(.vertical, DesignTokens.Spacing.md)
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    let vm: RepositoryViewModel = .preview
    StagingFilesColumn(
        viewModel: vm,
        staged: vm.status.stagedFiles,
        unstaged: vm.status.unstagedFiles,
        statusLoading: false
    )
    .frame(width: 380, height: 600)
    .background(theme.palette.bg1)
    .appTheme(theme)
}
