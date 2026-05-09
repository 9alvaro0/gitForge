import SwiftUI

/// `.gf-view-staging` — Changes view: file list + commit composer + diff pane.
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

    /// True only until the first `refreshStatus()` lands for this repo VM.
    /// Subsequent refreshes (watcher pulses, post-stage reloads…) keep the
    /// real data on screen — folding `isLoadingStatus` in here used to trap
    /// the skeleton on clean trees, where `staged.isEmpty && unstaged.isEmpty`
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
                ToolButton(.x, label: "Discard all") {
                    ui.discardAllConfirmVisible = true
                }
            }
            HStack(spacing: DesignTokens.Spacing.none) {
                filesColumn
                diffColumn
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.palette.bg2)
        // Driven by `WorkspaceUI.discardAllConfirmVisible` so the Repository ▸
        // Discard All Changes menu and the local "Discard all" tool button
        // share one presentation path.
        .confirmationDialog("Discard all changes?",
                            isPresented: $ui.discardAllConfirmVisible,
                            titleVisibility: .visible) {
            Button("Discard all", role: .destructive) {
                Task { await viewModel.discardChanges(viewModel.status.files) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All uncommitted changes will be lost — staged, unstaged, and untracked files included. This can't be undone.")
        }
    }

    private var filesColumn: some View {
        VStack(spacing: DesignTokens.Spacing.none) {
            ScrollView {
                if statusLoading && staged.isEmpty && unstaged.isEmpty {
                    statusPlaceholder
                } else {
                    LazyVStack(spacing: DesignTokens.Spacing.none) {
                        fileSectionHeader(title: "Staged", count: staged.count, action: "Unstage all") {
                            Task { await viewModel.unstage(staged) }
                        }
                        if staged.isEmpty {
                            Text("Nothing staged")
                                .font(AppFont.sans(12))
                                .foregroundStyle(theme.palette.fg3)
                                .italic()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, DesignTokens.Spacing.xxl)
                                .padding(.vertical, DesignTokens.Spacing.md)
                        } else {
                            ForEach(staged) { f in
                                StagingRow(file: f, viewModel: viewModel)
                            }
                        }
                        Divider().background(theme.palette.line)
                        fileSectionHeader(title: "Unstaged", count: unstaged.count, action: "Stage all") {
                            Task { await viewModel.stage(unstaged) }
                        }
                        ForEach(unstaged) { f in
                            StagingRow(file: f, viewModel: viewModel)
                        }
                    }
                }
            }
            commitBox
        }
        .frame(width: DesignTokens.Staging.filesWidth)
        .background(theme.palette.bg1)
        .overlay(alignment: .trailing) { Rectangle().fill(theme.palette.lineStrong).frame(width: DesignTokens.Stroke.regular) }
    }

    private static let placeholderPaths = [
        "Sources/Features/Repository/Staging/StagingView.swift",
        "Sources/Core/Git/GitCLI.swift",
        "Sources/Core/Models/WorkingCopyFile.swift",
        "Sources/DesignSystem/Components/Skeleton.swift",
        "README.md",
    ]

    private var statusPlaceholder: some View {
        LazyVStack(spacing: DesignTokens.Spacing.none) {
            placeholderSectionHeader(title: "Staged", count: 0)
            ForEach(0..<2, id: \.self) { index in
                placeholderRow(index: index)
            }
            Divider().background(theme.palette.line)
            placeholderSectionHeader(title: "Unstaged", count: 0)
            ForEach(2..<5, id: \.self) { index in
                placeholderRow(index: index)
            }
        }
        .skeleton(true)
    }

    @ViewBuilder
    private func placeholderSectionHeader(title: String, count: Int) -> some View {
        HStack {
            HStack(spacing: DesignTokens.Spacing.xs) {
                Text(title.uppercased())
                    .font(AppFont.mono(10.5, family: theme.monoFont))
                    .tracking(0.6)
                Text("(0)")
                    .font(AppFont.mono(10.5, family: theme.monoFont))
            }
            .foregroundStyle(theme.palette.fg3)
            Spacer()
        }
        .padding(.horizontal, DesignTokens.Spacing.xxl)
        .padding(.vertical, DesignTokens.Spacing.sm)
    }

    @ViewBuilder
    private func placeholderRow(index: Int) -> some View {
        let path = Self.placeholderPaths[index % Self.placeholderPaths.count]
        HStack(spacing: DesignTokens.Spacing.md) {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.xs)
                .fill(theme.palette.bg2)
                .frame(width: DesignTokens.IconSize.md, height: DesignTokens.IconSize.md)
            StatusTag(kind: .modified)
            Text(path)
                .font(AppFont.mono(11.5, family: theme.monoFont))
                .foregroundStyle(theme.palette.fg2)
                .lineLimit(1)
                .truncationMode(.head)
            Spacer()
        }
        .padding(.horizontal, DesignTokens.Spacing.xxl)
        .padding(.vertical, DesignTokens.Spacing.xs)
        .frame(height: DesignTokens.IconSize.huge)
    }

    @ViewBuilder
    private func fileSectionHeader(title: String, count: Int, action: String, onAction: @escaping () -> Void) -> some View {
        HStack {
            HStack(spacing: DesignTokens.Spacing.xs) {
                Text(title.uppercased())
                    .font(AppFont.mono(10.5, family: theme.monoFont))
                    .tracking(0.6)
                Text("(\(count))")
                    .font(AppFont.mono(10.5, family: theme.monoFont))
            }
            .foregroundStyle(theme.palette.fg3)
            Spacer()
            Button(action: onAction) {
                Text(action)
                    .font(AppFont.mono(10.5, family: theme.monoFont))
                    .foregroundStyle(theme.palette.accent)
                    .padding(.horizontal, DesignTokens.Spacing.sm).padding(.vertical, DesignTokens.Spacing.xxs)
                    .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.xs).fill(.clear))
                    .contentShape(.rect(cornerRadius: DesignTokens.Radius.xs))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, DesignTokens.Spacing.xxl)
        .padding(.vertical, DesignTokens.Spacing.sm)
    }

    private var diffColumn: some View {
        Group {
            if let file = viewModel.selectedWorkingCopyFile {
                DiffPane(
                    file: file.path,
                    hunks: viewModel.workingCopyDiff,
                    loading: viewModel.loadingWorkingCopyDiff,
                    emptyState: viewModel.workingCopyDiffEmptyState,
                    onOpenInEditor: { openInEditor(file: file) },
                    viewMode: diffMode
                )
            } else if !staged.isEmpty || !unstaged.isEmpty {
                EmptyState(icon: .diff, title: "Pick a file to see the diff",
                           subtitle: "Selection drives the right-hand pane.") { EmptyView() }
            } else if statusLoading {
                DiffPane(file: nil, hunks: [], loading: true, viewMode: diffMode)
            } else {
                EmptyState(icon: .check, title: "Working tree is clean",
                           subtitle: "No changes to stage.") { EmptyView() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var commitBox: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            TextField("Commit message", text: $commitMessage)
                .textFieldStyle(.plain)
                .padding(.horizontal, DesignTokens.Spacing.lg).padding(.vertical, DesignTokens.Spacing.md)
                .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).fill(theme.palette.bg3))
                .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).stroke(theme.palette.lineStrong, lineWidth: DesignTokens.Stroke.regular))
                .font(AppFont.sans(12.5))

            TextField("Description (optional)", text: $commitDescription, axis: .vertical)
                .lineLimit(3...3)
                .textFieldStyle(.plain)
                .padding(.horizontal, DesignTokens.Spacing.lg).padding(.vertical, DesignTokens.Spacing.md)
                .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).fill(theme.palette.bg3))
                .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).stroke(theme.palette.lineStrong, lineWidth: DesignTokens.Stroke.regular))
                .font(AppFont.mono(12, family: theme.monoFont))

            HStack {
                MonoText("on \(viewModel.currentBranchName ?? "HEAD") · \(staged.count) files", dim: true)
                Spacer()
                GFButton(title: "Commit & push") { Task { await commit(push: true) } }
                GFButton(title: "Commit", style: .primary,
                         disabled: commitMessage.isEmpty || staged.isEmpty) {
                    Task { await commit(push: false) }
                }
            }

            if let error = viewModel.commitError {
                Text(error)
                    .font(AppFont.mono(11, family: theme.monoFont))
                    .foregroundStyle(theme.palette.del)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(DesignTokens.Spacing.xl)
        .background(theme.palette.bg2)
        .overlay(alignment: .top) { Rectangle().fill(theme.palette.lineStrong).frame(height: DesignTokens.Stroke.regular) }
    }

    private func commit(push: Bool) async {
        viewModel.commitSubject = commitMessage
        viewModel.commitBody = commitDescription
        let ok = await viewModel.commit()
        if ok, push { await viewModel.push() }
        if ok { commitMessage = ""; commitDescription = "" }
    }

    private func openInEditor(file: WorkingCopyFile) {
        let absolute = viewModel.repository.url.appendingPathComponent(file.path)
        NSWorkspace.shared.open(absolute)
    }
}

private struct StagingRow: View {
    let file: WorkingCopyFile
    @Bindable var viewModel: RepositoryViewModel
    @Environment(\.appTheme) private var theme
    @State private var hovering = false
    /// Drives a per-row confirmation when the user picks "Discard changes"
    /// or "Delete file" on an untracked entry. Always confirms — there's no
    /// undo for this and the all-files variant already gates behind a dialog.
    @State private var pendingDiscard = false

    var body: some View {
        let isSelected = viewModel.selectedWorkingCopyFile?.id == file.id
        Button(action: { viewModel.selectedWorkingCopyFile = file }) {
            HStack(spacing: DesignTokens.Spacing.md) {
                Toggle("", isOn: Binding(
                    get: { file.isStaged },
                    set: { _ in Task { await toggleStaged() } }
                ))
                .toggleStyle(GFCheckboxStyle())
                StatusTag(kind: StatusTag.Kind(workingFile: file.isStaged ? file.stagedStatus : file.unstagedStatus))
                pathView
                Spacer()
                stats
            }
            .padding(.horizontal, DesignTokens.Spacing.xxl)
            .padding(.vertical, DesignTokens.Spacing.xs)
            .frame(height: DesignTokens.IconSize.huge)
            .background(isSelected ? theme.palette.bg4 : (hovering ? theme.palette.bg3 : .clear))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .simultaneousGesture(
            TapGesture(count: 2).onEnded { Task { await toggleStaged() } }
        )
        .help(file.isStaged ? "Double-click to unstage" : "Double-click to stage")
        .contextMenu { contextMenu }
        .confirmationDialog(
            file.isUntracked ? "Delete \(filename)?" : "Discard changes to \(filename)?",
            isPresented: $pendingDiscard,
            titleVisibility: .visible
        ) {
            Button(file.isUntracked ? "Delete file" : "Discard changes",
                   role: .destructive) {
                Task { await viewModel.discardChanges([file]) }
            }
        } message: {
            Text(file.isUntracked
                 ? "The file will be removed from disk. This can't be undone from the app."
                 : "Local changes will be reverted to the last committed version. This can't be undone.")
        }
    }

    @ViewBuilder
    private var contextMenu: some View {
        if file.isStaged {
            Button("Unstage") { Task { await viewModel.unstage([file]) } }
        } else {
            Button("Stage") { Task { await viewModel.stage([file]) } }
        }
        if file.isUntracked {
            Button("Delete file", role: .destructive) {
                pendingDiscard = true
            }
        } else {
            Button(file.isUnmerged ? "Discard conflict (revert to HEAD)" : "Discard changes",
                   role: .destructive) {
                pendingDiscard = true
            }
        }
        Divider()
        Button("Open in editor") {
            NSWorkspace.shared.open(absoluteURL)
        }
        Button("Reveal in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting([absoluteURL])
        }
        Divider()
        Button("Copy path") { copyToPasteboard(file.path) }
        Button("Copy filename") { copyToPasteboard(filename) }
    }

    private var absoluteURL: URL {
        viewModel.repository.url.appendingPathComponent(file.path)
    }

    private var filename: String {
        (file.path as NSString).lastPathComponent
    }

    private func copyToPasteboard(_ string: String) {
        NSPasteboard.general.declareTypes([.string], owner: nil)
        NSPasteboard.general.setString(string, forType: .string)
    }

    private func toggleStaged() async {
        if file.isStaged { await viewModel.unstage([file]) }
        else             { await viewModel.stage([file]) }
    }

    private var pathView: some View {
        let parts = file.path.split(separator: "/")
        let directory = parts.dropLast().joined(separator: "/")
        let name = parts.last.map(String.init) ?? file.path
        return HStack(spacing: DesignTokens.Spacing.none) {
            if !directory.isEmpty {
                Text("\(directory)/")
                    .font(AppFont.mono(11.5, family: theme.monoFont))
                    .foregroundStyle(theme.palette.fg3)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Text(name)
                .font(AppFont.mono(11.5, family: theme.monoFont))
                .foregroundStyle(theme.palette.fg1)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var stats: some View {
        EmptyView()
    }
}

private extension StatusTag.Kind {
    /// Maps a working-copy status to the visual badge. `.unmodified` collapses
    /// to `.modified` so partially-staged files (where one side is unmodified)
    /// still render a badge in the row instead of disappearing.
    init(workingFile: WorkingCopyFile.Status) {
        switch workingFile {
        case .modified, .typeChanged: self = .modified
        case .added:                  self = .added
        case .deleted:                self = .deleted
        case .renamed:                self = .renamed
        case .copied:                 self = .copied
        case .untracked:              self = .untracked
        case .unmerged:               self = .unmerged
        case .ignored:                self = .ignored
        case .unmodified:             self = .modified
        }
    }
}

#if DEBUG
#Preview("Loaded") {
    @Previewable @State var theme = AppTheme()
    StagingView(viewModel: RepositoryViewModel.preview)
        .frame(width: 1100, height: 700)
        .appTheme(theme)
}

#Preview("Loading status") {
    @Previewable @State var theme = AppTheme()
    let vm: RepositoryViewModel = {
        let v = RepositoryViewModel.preview
        v.status = WorkingCopyStatus(files: [])
        v.isLoadingStatus = true
        return v
    }()
    StagingView(viewModel: vm)
        .frame(width: 1100, height: 700)
        .appTheme(theme)
}
#endif

/// Square checkbox styled like the design `.gf-file-row input[type=checkbox]`.
struct GFCheckboxStyle: ToggleStyle {
    @Environment(\.appTheme) private var theme

    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.xs)
                    .fill(configuration.isOn ? theme.palette.accent : theme.palette.bg2)
                RoundedRectangle(cornerRadius: DesignTokens.Radius.xs)
                    .stroke(configuration.isOn ? theme.palette.accent : theme.palette.lineStrong, lineWidth: DesignTokens.Stroke.regular)
                if configuration.isOn {
                    Image(systemName: "checkmark")
                        .font(.system(size: FontSize.caption, weight: .bold))
                        .foregroundStyle(theme.palette.accentFg)
                }
            }
            .frame(width: DesignTokens.IconSize.md, height: DesignTokens.IconSize.md)
            .contentShape(.rect(cornerRadius: DesignTokens.Radius.xs))
        }
        .buttonStyle(.plain)
    }
}
