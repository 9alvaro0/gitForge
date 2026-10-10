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
                    .navigationTitle("Conflicts")
            }
        }
        .task { await viewModel.loadConflictState() }
        .confirmationDialog("Abort stash apply?",
                            isPresented: $confirmAbortStash,
                            titleVisibility: .visible) {
            Button("Abort", role: .destructive) { Task { await runAbortStashApply() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Reverts the files this stash changed back to HEAD. Your other local changes are kept, and the stash entry stays in the list so you can re-apply it later.")
        }
    }

    private var resolverShell: some View {
        VStack(spacing: DesignTokens.Spacing.none) {
            HStack(spacing: DesignTokens.Spacing.none) {
                ConflictFilesColumn(viewModel: viewModel)
                ConflictHunksColumn(viewModel: viewModel)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.palette.bg2)
        .navigationTitle("Resolve conflicts")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                switch viewModel.mergeState {
                case .unmerged:
                    // Stash apply has no `--abort` in git; the VM reverts the
                    // paths the stash touched. Confirm because it discards
                    // the half-applied stash content from the worktree.
                    Button { confirmAbortStash = true } label: {
                        Label("Abort stash apply", systemImage: "xmark")
                    }
                    .labelStyle(.iconOnly)
                    .help("Abort stash apply…")
                case .bisecting:
                    // No native conflict resolution loop for bisect; the user
                    // marks good/bad from terminal. Surface the situation so
                    // they're not blindly hitting Continue.
                    Text("Bisect in progress — finish from terminal with `git bisect reset`.")
                        .textRole(.callout)
                        .foregroundStyle(theme.colors.textTertiary)
                case .clean:
                    EmptyView()
                case .merging, .rebasing, .cherryPicking, .reverting:
                    Button { Task { await viewModel.abortMerge() } } label: {
                        Label("Abort \(operationLabel)", systemImage: "xmark")
                    }
                    .labelStyle(.iconOnly)
                    .help("Abort \(operationLabel)")
                    Button { Task { await viewModel.continueMerge() } } label: {
                        Label("Continue \(operationLabel)", systemImage: "checkmark")
                    }
                    .labelStyle(.titleAndIcon)
                    .buttonStyle(.glassProminent)
                    .disabled(!viewModel.conflicts.files.allSatisfy(\.resolved))
                }
            }
        }
    }

    private var operationLabel: String {
        switch viewModel.mergeState {
        case .merging:       return "merge"
        case .rebasing:      return "rebase"
        case .cherryPicking: return "cherry-pick"
        case .reverting:     return "revert"
        default:             return ""
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
