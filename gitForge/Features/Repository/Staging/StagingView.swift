import SwiftUI

struct StagingView: View {
    @Bindable var viewModel: RepositoryViewModel

    @Environment(AppState.self) private var appState
    @Environment(WorkspaceUI.self) private var ui
    @Environment(\.appTheme) private var theme
    @State private var commitMessage: String = ""
    @State private var commitDescription: String = ""
    @State private var diffModeOverride: DiffPane.ViewMode?

    private var diffMode: Binding<DiffPane.ViewMode> {
        Binding(
            get: { diffModeOverride ?? theme.defaultDiffMode },
            set: { diffModeOverride = $0 }
        )
    }

    private var staged: [WorkingCopyFile]   { viewModel.status.stagedFiles }
    private var unstaged: [WorkingCopyFile] { viewModel.status.unstagedFiles }

    /// True only until the first refreshStatus() lands for this repo VM.
    /// Subsequent refreshes (watcher pulses, post-stage reloads…) keep the real
    /// data on screen — folding `isLoadingStatus` here used to trap the
    /// skeleton on clean trees, where `staged.isEmpty && unstaged.isEmpty`
    /// stayed true and the loading flag won the race against the (empty)
    /// status payload arriving.
    private var statusLoading: Bool {
        !viewModel.hasLoadedStatusOnce
    }

    var body: some View {
        @Bindable var ui = ui
        VStack(spacing: DesignTokens.Spacing.none) {
            ContentHeader(title: "Changes") {
                MonoText("\(staged.count) staged · \(unstaged.count) unstaged", dim: true)
            } right: {
                ToolButton(.stash, label: "Stash") { Task { _ = await viewModel.stashAll() } }
                ToolButton(.x, label: "Discard all") { ui.discardAllConfirmVisible = true }
            }
            HStack(spacing: DesignTokens.Spacing.none) {
                filesPane
                StagingDiffColumn(
                    viewModel: viewModel,
                    hasFiles: !staged.isEmpty || !unstaged.isEmpty,
                    statusLoading: statusLoading,
                    diffMode: diffMode
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.palette.bg2)
        // Driven by WorkspaceUI.discardAllConfirmVisible so the Repository ▸
        // Discard All Changes menu and the local "Discard all" tool button
        // share one presentation path.
        .confirmationDialog("Discard all changes?",
                            isPresented: $ui.discardAllConfirmVisible,
                            titleVisibility: .visible) {
            // Cancel is bound to the default Return so a reflexive press
            // doesn't wipe the working tree. The destructive choice stays
            // available — just no longer one-keystroke away.
            Button("Cancel", role: .cancel) {}
                .keyboardShortcut(.defaultAction)
            Button("Discard all", role: .destructive) {
                Task { await viewModel.discardChanges(viewModel.status.files) }
            }
        } message: {
            Text("All uncommitted changes will be lost — staged, unstaged, and untracked files included. This can't be undone.")
        }
    }

    private var filesPane: some View {
        VStack(spacing: DesignTokens.Spacing.none) {
            StagingFilesColumn(
                viewModel: viewModel,
                staged: staged,
                unstaged: unstaged,
                statusLoading: statusLoading
            )
            StagingCommitBox(
                viewModel: viewModel,
                stagedCount: staged.count,
                commitMessage: $commitMessage,
                commitDescription: $commitDescription
            )
        }
        .frame(width: DesignTokens.Staging.filesWidth)
        .background(theme.palette.bg1)
        .overlay(alignment: .trailing) { Rectangle().fill(theme.palette.lineStrong).frame(width: DesignTokens.Stroke.regular) }
    }
}

#Preview("Loaded") {
    @Previewable @State var theme = AppTheme()
    StagingView(viewModel: .preview)
        .previewAppState(.preview)
        .frame(width: 1100, height: 700)
        .appTheme(theme)
}

#Preview("Loading status") {
    @Previewable @State var theme = AppTheme()
    StagingView(viewModel: .previewLoadingStatus)
        .previewAppState(.preview)
        .frame(width: 1100, height: 700)
        .appTheme(theme)
}

#Preview("Clean tree") {
    @Previewable @State var theme = AppTheme()
    StagingView(viewModel: .previewCleanTree)
        .previewAppState(.preview)
        .frame(width: 1100, height: 700)
        .appTheme(theme)
}
