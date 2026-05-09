import SwiftUI

/// Action grid (Branch / Tag / Cherry-pick / Revert) plus Reset menu under
/// the commit detail panel. Owns its own sheet/dialog state — the runners
/// emit toasts via `AppState.ui.activeToast` and route conflicts to the
/// Conflicts view through `appState.ui.workspaceSection`.
struct CommitActionsSection: View {
    let commit: Commit
    @Bindable var viewModel: RepositoryViewModel

    @Environment(AppState.self) private var appState
    @Environment(\.appTheme) private var theme

    @State private var newBranchSheet = false
    @State private var newBranchName: String = ""
    @State private var cherryPickConfirm = false
    @State private var revertConfirm = false
    @State private var resetMode: GitCLI.ResetMode?
    @State private var newTagSheet = false
    @State private var newTagName: String = ""
    @State private var newTagMessage: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            Text("ACTIONS")
                .font(.system(size: FontSize.footnote, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(theme.palette.fg3)
            actionGrid
            resetMenu
        }
        .sheet(isPresented: $newBranchSheet) {
            CommitBranchSheet(
                commitShortSha: commit.shortSha,
                name: $newBranchName,
                onCancel: { newBranchSheet = false },
                onConfirm: { Task { await runCreateBranch() } }
            )
        }
        .sheet(isPresented: $newTagSheet) {
            CommitTagSheet(
                commitShortSha: commit.shortSha,
                name: $newTagName,
                message: $newTagMessage,
                onCancel: { newTagSheet = false },
                onConfirm: { Task { await runCreateTag() } }
            )
        }
        .confirmationDialog("Cherry-pick \(commit.shortSha)?",
                            isPresented: $cherryPickConfirm,
                            titleVisibility: .visible) {
            Button("Cherry-pick") { Task { await runCherryPick() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Replays the changes from this commit on top of the current branch.")
        }
        .confirmationDialog("Revert \(commit.shortSha)?",
                            isPresented: $revertConfirm,
                            titleVisibility: .visible) {
            Button("Revert") { Task { await runRevert() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Creates a new commit that undoes the changes from this commit.")
        }
        .confirmationDialog("Reset to \(commit.shortSha)?",
                            isPresented: resetConfirmBinding,
                            titleVisibility: .visible) {
            Button(resetMode == .hard ? "Reset (destructive)" : "Reset",
                   role: resetMode == .hard ? .destructive : nil) {
                if let mode = resetMode { Task { await runReset(mode: mode) } }
            }
            Button("Cancel", role: .cancel) { resetMode = nil }
        } message: {
            Text(resetMode?.label ?? "")
        }
    }

    private var actionGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: DesignTokens.Spacing.sm),
                GridItem(.flexible(), spacing: DesignTokens.Spacing.sm)
            ],
            spacing: DesignTokens.Spacing.sm
        ) {
            CommitActionButton(
                icon: .branch, title: "Branch",
                tooltip: "Create a new branch starting at \(commit.shortSha)."
            ) {
                newBranchName = ""
                newBranchSheet = true
            }
            CommitActionButton(
                icon: .square, title: "Tag",
                tooltip: "Create a tag pointing at \(commit.shortSha)."
            ) {
                newTagName = ""
                newTagMessage = ""
                newTagSheet = true
            }
            CommitActionButton(
                icon: .plus, title: "Cherry-pick",
                tooltip: "Replay this commit on top of the current branch."
            ) {
                cherryPickConfirm = true
            }
            CommitActionButton(
                icon: .arrowU, title: "Revert",
                tooltip: "Create a new commit that undoes the changes from \(commit.shortSha)."
            ) {
                revertConfirm = true
            }
        }
    }

    private var resetMenu: some View {
        Menu {
            ForEach(GitCLI.ResetMode.allCases) { mode in
                Button(mode.label) { resetMode = mode }
            }
        } label: {
            CommitActionButtonLabel(
                icon: .warn,
                title: "Reset to here",
                destructive: true,
                trailingChevron: true
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .help("Move HEAD of the current branch to \(commit.shortSha). Soft / mixed / hard control how the working tree is affected — hard discards uncommitted changes.")
    }

    private var resetConfirmBinding: Binding<Bool> {
        Binding(get: { resetMode != nil }, set: { if !$0 { resetMode = nil } })
    }

    @MainActor
    private func runCreateBranch() async {
        let name = newBranchName
        let sha = commit.sha
        _ = await viewModel.createBranch(name: name, startingAt: sha, checkout: true)
        newBranchSheet = false
    }

    @MainActor
    private func runCreateTag() async {
        let name = newTagName
        let message = newTagMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        let result = await viewModel.createTag(
            name: name,
            at: commit.sha,
            message: message.isEmpty ? nil : message
        )
        switch result {
        case .success:
            appState.ui.activeToast = ToastMessage(message: "Tagged \(commit.shortSha) as \(name)", kind: .ok)
            newTagSheet = false
        case .failure(let err):
            appState.ui.activeToast = ToastMessage(
                message: (err as? LocalizedError)?.errorDescription ?? err.localizedDescription,
                kind: .error
            )
        }
    }

    @MainActor
    private func runCherryPick() async {
        appState.ui.emitToast(
            for: await viewModel.cherryPick(commit),
            success: "Cherry-picked \(commit.shortSha)",
            conflicts: "Cherry-pick has conflicts — resolve to continue"
        )
    }

    @MainActor
    private func runRevert() async {
        appState.ui.emitToast(
            for: await viewModel.revert(commit),
            success: "Reverted \(commit.shortSha)",
            conflicts: "Revert has conflicts — resolve to continue"
        )
    }

    @MainActor
    private func runReset(mode: GitCLI.ResetMode) async {
        appState.ui.emitToast(
            for: await viewModel.reset(to: commit.sha, mode: mode),
            success: "Reset \(mode.rawValue) to \(commit.shortSha)",
            conflicts: "Reset has conflicts — resolve to continue"
        )
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    CommitActionsSection(commit: .preview, viewModel: .preview)
        .previewAppState(.preview)
        .padding()
        .frame(width: 380)
        .background(theme.palette.bg1)
        .appTheme(theme)
}
