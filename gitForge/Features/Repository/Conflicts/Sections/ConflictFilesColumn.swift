import SwiftUI

struct ConflictFilesColumn: View {
    @Bindable var viewModel: RepositoryViewModel
    @Environment(\.appTheme) private var theme

    private var files: [ConflictFile] { viewModel.conflictFiles }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.none) {
            header
            if files.isEmpty {
                Text("No unresolved files.")
                    .font(AppFont.sans(12))
                    .foregroundStyle(theme.palette.fg3)
                    .padding(DesignTokens.Spacing.xxl)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: DesignTokens.Spacing.none) {
                        ForEach(files) { file in
                            ConflictFileRow(
                                file: file,
                                isSelected: file.path == viewModel.selectedConflictPath,
                                absoluteURL: viewModel.repository.url.appendingPathComponent(file.path),
                                onSelect: { Task { await viewModel.loadConflictHunks(for: file.path) } },
                                onResolveOurs: { Task { await viewModel.resolveFile(at: file.path, using: .ours) } },
                                onResolveTheirs: { Task { await viewModel.resolveFile(at: file.path, using: .theirs) } },
                                onDiscard: { Task { await viewModel.discardChanges(workingCopyFile(for: file)) } }
                            )
                        }
                    }
                }
            }
        }
        .frame(width: DesignTokens.Conflict.filesWidth)
        .background(theme.palette.bg1)
        .overlay(alignment: .trailing) { Rectangle().fill(theme.palette.lineStrong).frame(width: DesignTokens.Stroke.regular) }
    }

    private var header: some View {
        Text("Files with conflicts".uppercased())
            .font(.system(size: FontSize.footnote, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(theme.palette.fg3)
            .padding(.horizontal, DesignTokens.Spacing.xxl)
            .padding(.vertical, DesignTokens.Spacing.md)
    }

    /// Bridges to `[WorkingCopyFile]` so the unmerged-aware discard path on
    /// the view-model can be reused.
    private func workingCopyFile(for file: ConflictFile) -> [WorkingCopyFile] {
        guard let match = viewModel.status.files.first(where: { $0.path == file.path }) else {
            return []
        }
        return [match]
    }
}
