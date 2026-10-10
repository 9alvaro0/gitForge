import SwiftUI

struct StagingView: View {
    @Bindable var viewModel: RepositoryViewModel

    @Environment(AppState.self) private var appState
    @Environment(WorkspaceUI.self) private var ui
    @Environment(\.appTheme) private var theme
    @Environment(\.appPreferences) private var preferences
    @State private var diffModeOverride: DiffPane.ViewMode?
    @State private var filesWidth: CGFloat = {
        let stored = UserDefaults.standard.double(forKey: StagingView.filesWidthKey)
        let resolved = stored > 0 ? CGFloat(stored) : StagingView.defaultFilesWidth
        return min(max(StagingView.minFilesWidth, resolved), StagingView.maxFilesWidth)
    }()

    private static let filesWidthKey = "gitForge.changes.filesPanelWidth"
    private static let defaultFilesWidth: CGFloat = 440
    private static let minFilesWidth: CGFloat = 340
    private static let maxFilesWidth: CGFloat = 600
    private static let minDiffWidth: CGFloat = 420

    private var diffMode: Binding<DiffPane.ViewMode> {
        Binding(
            get: { diffModeOverride ?? preferences.defaultDiffMode },
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
        GeometryReader { geo in
            let cap = filesCap(available: geo.size.width)
            HStack(spacing: 0) {
                filesPane
                    .frame(width: min(filesWidth, cap))
                ColumnDragHandle(
                    // Reads and writes the width actually shown, so a drag
                    // past the cap can't bank invisible width.
                    width: Binding(
                        get: { min(filesWidth, cap) },
                        set: { filesWidth = min($0, cap) }
                    ),
                    minWidth: Self.minFilesWidth,
                    maxWidth: cap,
                    dividerColor: theme.colors.separator,
                    onCommit: {
                        UserDefaults.standard.set(Double(filesWidth), forKey: Self.filesWidthKey)
                    }
                )
                StagingDiffColumn(
                    viewModel: viewModel,
                    hasFiles: !staged.isEmpty || !unstaged.isEmpty,
                    statusLoading: statusLoading,
                    diffMode: diffMode
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.colors.bgContent)
        .navigationTitle("Changes")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { Task { _ = await viewModel.stashAll() } } label: {
                    Label("Stash all", systemImage: "tray.and.arrow.down")
                }
                .labelStyle(.titleAndIcon)
                .help("Stash all changes")
                Button { ui.discardAllConfirmVisible = true } label: {
                    Label("Discard all…", systemImage: "trash")
                        .foregroundStyle(theme.colors.del)
                }
                .labelStyle(.titleAndIcon)
                .help("Discard all changes…")
            }
        }
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
        VStack(spacing: 0) {
            StagingFilesColumn(
                viewModel: viewModel,
                staged: staged,
                unstaged: unstaged,
                statusLoading: statusLoading
            )
            StagingCommitBox(viewModel: viewModel, stagedCount: staged.count)
        }
    }

    /// Widest the file list may be so the diff keeps `minDiffWidth`.
    private func filesCap(available: CGFloat) -> CGFloat {
        let handle = Spacing.s8
        return min(Self.maxFilesWidth, max(Self.minFilesWidth, available - Self.minDiffWidth - handle))
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
