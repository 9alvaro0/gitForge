import SwiftUI

/// The "…" menu in the commit inspector's header: new branch or tag here,
/// cherry-pick, revert, and reset to here. A menu instead of a grid of
/// buttons, so the inspector's height goes to the files and the diff (audit
/// M5). Owns its own sheet/dialog state — the runners emit toasts via
/// `AppState.ui.activeToast` and route conflicts to the Conflicts view
/// through `appState.ui.workspaceSection`.
struct CommitActionsMenu: View {
    let commit: Commit
    @Bindable var viewModel: RepositoryViewModel

    @Environment(AppState.self) private var appState

    @State private var newBranchSheet = false
    @State private var newBranchName: String = ""
    @State private var cherryPickConfirm = false
    @State private var revertConfirm = false
    @State private var resetMode: GitCLI.ResetMode?
    @State private var newTagSheet = false
    @State private var newTagName: String = ""
    @State private var newTagMessage: String = ""

    var body: some View {
        OverflowMenu(accessibilityLabel: String(localized: "Commit actions")) {
            Button("New branch…") {
                newBranchName = ""
                newBranchSheet = true
            }
            .help("Create a new branch starting at \(commit.shortSha).")
            Button("New tag…") {
                newTagName = ""
                newTagMessage = ""
                newTagSheet = true
            }
            .help("Create a tag pointing at \(commit.shortSha).")
            Divider()
            Button("Cherry-pick…") { cherryPickConfirm = true }
                .help("Replay this commit on top of the current branch.")
            Button("Revert…") { revertConfirm = true }
                .help("Create a new commit that undoes the changes from \(commit.shortSha).")
            Divider()
            Menu("Reset to here") {
                ForEach(GitCLI.ResetMode.allCases) { mode in
                    Button(mode.label) { resetMode = mode }
                }
            }
            .help("Move HEAD of the current branch to \(commit.shortSha). Soft / mixed / hard control how the working tree is affected — hard discards uncommitted changes.")
        }
        .help("Commit actions")
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
            Button(resetMode == .hard ? String(localized: "Reset (destructive)") : String(localized: "Reset"),
                   role: resetMode == .hard ? .destructive : nil) {
                if let mode = resetMode { Task { await runReset(mode: mode) } }
            }
            Button("Cancel", role: .cancel) { resetMode = nil }
        } message: {
            Text(Self.resetConfirmMessage(for: resetMode, shortSha: commit.shortSha))
        }
    }

    static func resetConfirmMessage(for mode: GitCLI.ResetMode?, shortSha: String) -> String {
        guard let mode else { return "" }
        switch mode {
        case .soft:
            return String(localized: "Moves HEAD to \(shortSha). Commits between current HEAD and this one stay as staged changes. Working tree is untouched.")
        case .mixed:
            return String(localized: "Moves HEAD to \(shortSha). Commits between current HEAD and this one stay as unstaged changes. Working tree is untouched.")
        case .hard:
            return String(localized: "Moves HEAD to \(shortSha) and DISCARDS every commit and uncommitted change after it. Recoverable only via `git reflog` for a limited time. This cannot be undone from the UI.")
        }
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
            appState.ui.activeToast = ToastMessage(message: String(localized: "Tagged \(commit.shortSha) as \(name)"), kind: .ok)
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
            success: String(localized: "Cherry-picked \(commit.shortSha)"),
            conflicts: String(localized: "Cherry-pick has conflicts — resolve to continue")
        )
    }

    @MainActor
    private func runRevert() async {
        appState.ui.emitToast(
            for: await viewModel.revert(commit),
            success: String(localized: "Reverted \(commit.shortSha)"),
            conflicts: String(localized: "Revert has conflicts — resolve to continue")
        )
    }

    @MainActor
    private func runReset(mode: GitCLI.ResetMode) async {
        appState.ui.emitToast(
            for: await viewModel.reset(to: commit.sha, mode: mode),
            success: String(localized: "Reset \(mode.rawValue) to \(commit.shortSha)"),
            conflicts: String(localized: "Reset has conflicts — resolve to continue")
        )
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    CommitActionsMenu(commit: .preview, viewModel: .preview)
        .previewAppState(.preview)
        .padding()
        .background(theme.colors.bgElevated)
        .appTheme(theme)
}
