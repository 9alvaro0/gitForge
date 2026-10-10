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
                           subtitle: "Conflicts will show up here when a merge or rebase pauses.")
                    .background(theme.colors.bgContent)
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
        HStack(spacing: 0) {
            ConflictFilesColumn(viewModel: viewModel)
            Rectangle().fill(theme.colors.separator).frame(width: 1)
            selectedFile
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.colors.bgContent)
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

    /// Header, then the hunks over the result (60 / 40, or 30 / 70 while the
/// result is edited by hand).
    @ViewBuilder
    private var selectedFile: some View {
        let conflicts = viewModel.conflicts
        if let path = conflicts.selectedPath, !conflicts.hunks.isEmpty {
            VStack(spacing: 0) {
                ConflictFileHeader(
                    path: path,
                    hunkCount: conflicts.hunks.count,
                    pickedCount: conflicts.hunks.filter { conflicts.picks[$0.id] != nil }.count,
                    isManual: conflicts.manualText != nil,
                    canMarkResolved: conflicts.canMarkResolved,
                    currentBranchName: viewModel.currentBranchName,
                    onTakeOurs: { Task { await viewModel.resolveFile(at: path, using: .ours) } },
                    onTakeTheirs: { Task { await viewModel.resolveFile(at: path, using: .theirs) } },
                    onOpenInEditor: { ExternalURL.openFile(viewModel.repository.url.appendingPathComponent(path)) },
                    onMarkResolved: { Task { await viewModel.resolveSelectedFile() } }
                )
                GeometryReader { geo in
                    let manual = conflicts.manualText != nil
                    VStack(spacing: 0) {
                        // While the result is edited by hand the picks are
                        // paused, and the editor gets most of the height.
                        ConflictHunksColumn(viewModel: viewModel)
                            .disabled(manual)
                            .opacity(manual ? 0.45 : 1)
                            .frame(height: geo.size.height * (manual ? 0.3 : 0.6))
                        Rectangle().fill(theme.colors.separator).frame(height: 1)
                        ConflictResultPanel(
                            lines: conflicts.resultLines,
                            manualText: Bindable(conflicts).manualText,
                            manualTextHasMarkers: conflicts.manualTextHasMarkers,
                            onEdit: { conflicts.beginManualEdit() },
                            onDiscardEdits: { conflicts.discardManualEdit() }
                        )
                    }
                    .animation(DesignTokens.Motion.standard, value: manual)
                }
            }
        } else if conflicts.selectedPath != nil {
            EmptyState(icon: .check, title: "No conflicts left in this file",
                       subtitle: "Pick another file on the left, or continue when every file is resolved.")
        } else {
            EmptyState(icon: .conflict, title: "Pick a conflicted file")
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
