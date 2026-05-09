import SwiftUI

struct ConflictView: View {
    @Bindable var viewModel: RepositoryViewModel
    @Environment(\.appTheme) private var theme

    var body: some View {
        Group {
            if viewModel.mergeState.isInProgress {
                resolverShell
            } else {
                EmptyState(icon: .check, title: "No merge in progress",
                           subtitle: "Conflicts will show up here when a merge or rebase pauses.") { EmptyView() }
                    .background(theme.palette.bg2)
            }
        }
        .task { await viewModel.loadConflictState() }
    }

    private var resolverShell: some View {
        VStack(spacing: DesignTokens.Spacing.none) {
            ContentHeader(title: "Resolve conflicts") {
                MonoText(headerSubtitle, dim: true)
            } right: {
                // `.unmerged` (stash apply conflict) has no native abort /
                // continue commands — the user resolves files and commits
                // normally. Hide both buttons in that case.
                if viewModel.mergeState != .unmerged {
                    ToolButton(.x, label: "Abort \(viewModel.mergeState == .rebasing ? "rebase" : "merge")") {
                        Task { await viewModel.abortMerge() }
                    }
                    ToolButton(.check,
                               label: "Continue \(viewModel.mergeState == .rebasing ? "rebase" : "merge")",
                               primary: true,
                               disabled: !viewModel.conflictFiles.allSatisfy(\.resolved)) {
                        Task { await viewModel.continueMerge() }
                    }
                }
            }
            HStack(spacing: DesignTokens.Spacing.none) {
                ConflictFilesColumn(viewModel: viewModel)
                ConflictHunksColumn(viewModel: viewModel)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.palette.bg2)
    }

    private var headerSubtitle: String {
        switch viewModel.mergeState {
        case .merging:  return "merging into \(viewModel.currentBranchName ?? "HEAD")"
        case .rebasing: return "rebasing \(viewModel.currentBranchName ?? "HEAD")"
        case .unmerged: return "applying stash on \(viewModel.currentBranchName ?? "HEAD")"
        case .clean:    return ""
        }
    }
}

#Preview("Resolving merge") {
    @Previewable @State var theme = AppTheme()
    ConflictView(viewModel: .previewWithConflicts)
        .frame(width: 1100, height: 700)
        .appTheme(theme)
}

#Preview("Empty (clean tree)") {
    @Previewable @State var theme = AppTheme()
    ConflictView(viewModel: .preview)
        .frame(width: 1100, height: 700)
        .appTheme(theme)
}
