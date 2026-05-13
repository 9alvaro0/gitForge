import SwiftUI

struct ConflictView: View {
    @Bindable var viewModel: RepositoryViewModel
    @Environment(\.appTheme) private var theme
    @Environment(AppState.self) private var appState
    @State private var confirmAbortStash = false

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
        .confirmationDialog("Abort stash apply?",
                            isPresented: $confirmAbortStash,
                            titleVisibility: .visible) {
            Button("Abort", role: .destructive) { Task { await runAbortStashApply() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Resets the working tree to HEAD and drops the partial stash application. The stash entry itself stays in the list — you can re-apply it later.")
        }
    }

    private var resolverShell: some View {
        VStack(spacing: DesignTokens.Spacing.none) {
            ContentHeader(title: "Resolve conflicts") {
                MonoText(headerSubtitle, dim: true)
            } right: {
                if viewModel.mergeState == .unmerged {
                    // Stash apply has no `--abort` in git — `reset --hard HEAD`
                    // is the equivalent. Confirm because it discards the
                    // half-applied stash content from the worktree.
                    ToolButton(.x, label: "Abort stash apply") {
                        confirmAbortStash = true
                    }
                } else {
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

    private func runAbortStashApply() async {
        switch await viewModel.abortStashApply() {
        case .success:
            appState.ui.activeToast = ToastMessage(message: "Stash apply aborted", kind: .ok)
        case .failure(let error):
            appState.ui.activeToast = ToastMessage(
                message: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription,
                kind: .error
            )
        }
    }
}

#Preview("Resolving merge") {
    @Previewable @State var theme = AppTheme()
    ConflictView(viewModel: .previewWithConflicts)
        .previewAppState(.preview)
        .frame(width: 1100, height: 700)
        .appTheme(theme)
}

#Preview("Empty (clean tree)") {
    @Previewable @State var theme = AppTheme()
    ConflictView(viewModel: .preview)
        .previewAppState(.preview)
        .frame(width: 1100, height: 700)
        .appTheme(theme)
}
