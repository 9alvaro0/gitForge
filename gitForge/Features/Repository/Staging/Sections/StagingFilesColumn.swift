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
        // Selected counts per section drive the action button label —
        // "Unstage 3 selected" when the user has ticks within the section,
        // "Unstage all" when they don't.
        let stagedSelectedCount = staged.filter { viewModel.selectedFilePaths.contains($0.path) }.count
        let unstagedSelectedCount = unstaged.filter { viewModel.selectedFilePaths.contains($0.path) }.count
        return LazyVStack(spacing: DesignTokens.Spacing.none) {
            StagingFileSectionHeader(
                title: "Staged",
                count: staged.count,
                actionLabel: stagedSelectedCount > 0
                    ? "Unstage \(stagedSelectedCount) selected"
                    : "Unstage all"
            ) {
                if stagedSelectedCount > 0 {
                    Task { await viewModel.unstageSelected() }
                } else {
                    Task { await viewModel.unstage(staged) }
                }
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
                actionLabel: unstagedSelectedCount > 0
                    ? "Stage \(unstagedSelectedCount) selected"
                    : "Stage all"
            ) {
                if unstagedSelectedCount > 0 {
                    Task { await viewModel.stageSelected() }
                } else {
                    Task { await viewModel.stage(unstaged) }
                }
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
