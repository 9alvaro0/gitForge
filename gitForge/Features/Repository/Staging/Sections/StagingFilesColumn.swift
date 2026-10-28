import SwiftUI

/// Unstaged above Staged, each with its select-all header, rows and — while
/// some of its files are ticked — the batch bar.
///
/// Ticking works like a Finder list: ⌘-click flips a row, Shift-click and
/// Shift-↑↓ tick a run (`StagingTicking`), Space ticks the open row, ⌘A ticks
/// its whole section, Esc unticks everything and ⌘⌫ discards the ticked
/// files — or the open one — after asking.
struct StagingFilesColumn: View {
    @Bindable var viewModel: RepositoryViewModel
    let staged: [WorkingCopyFile]
    let unstaged: [WorkingCopyFile]
    let statusLoading: Bool
    /// The toolbar filter is hiding files: empty sections say "No matches".
    var isFiltering = false

    @Environment(\.appTheme) private var theme
    @FocusState private var listFocused: Bool
    /// Files ⌘⌫ or a row's batch menu is asking to discard.
    @State private var pendingDiscard: [WorkingCopyFile]?

    private var unstagedRows: [WorkingCopyRowID] {
        unstaged.map { WorkingCopyRowID(side: .unstaged, path: $0.path) }
    }

    private var stagedRows: [WorkingCopyRowID] {
        staged.map { WorkingCopyRowID(side: .staged, path: $0.path) }
    }

    /// Unstaged then Staged, the order ↑↓ walks them in.
    private var rowIDs: [WorkingCopyRowID] { unstagedRows + stagedRows }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Group {
                    if statusLoading && staged.isEmpty && unstaged.isEmpty {
                        StagingLoadingPlaceholder()
                    } else {
                        fileList
                    }
                }
                .padding(Spacing.s8)
            }
            .listKeyboardNavigation(
                ids: rowIDs,
                selection: viewModel.workingCopy.selectedRowID,
                isFocused: $listFocused,
                scrollProxy: proxy,
                onShiftMove: { offset in
                    viewModel.workingCopy.extendTicks(by: offset, sections: [unstagedRows, stagedRows])
                }
            ) { id in
                open(id)
            }
            .onKeyPress(.space) { tickOpenRow() }
            .onKeyPress(.escape) {
                viewModel.workingCopy.clearTicks() ? .handled : .ignored
            }
            .background {
                // ⌘A and ⌘⌫ never reach `onKeyPress`, and Edit ▸ Select All
                // would take ⌘A.
                KeyEquivalentCatcher { characters, modifiers in
                    switch StagingKeyCommand(characters: characters, modifiers: modifiers) {
                    case .tickSection: tickOpenSection(); return true
                    case .discard: discardTickedOrOpen(); return true
                    case nil: return false
                    }
                }
            }
        }
        .confirmationDialog(
            discardTitle,
            isPresented: Binding(get: { pendingDiscard != nil }, set: { if !$0 { pendingDiscard = nil } }),
            titleVisibility: .visible,
            presenting: pendingDiscard
        ) { files in
            // Cancel stays the default so a reflexive Return doesn't wipe work.
            Button("Cancel", role: .cancel) {}
                .keyboardShortcut(.defaultAction)
            Button(discardButtonTitle(files), role: .destructive) {
                Task {
                    await viewModel.discardChanges(files)
                    viewModel.workingCopy.deselect(files)
                }
            }
        } message: { files in
            Text(discardMessage(files))
        }
    }

    private var fileList: some View {
        LazyVStack(spacing: 0) {
            section(
                title: String(localized: "Unstaged"),
                files: unstaged,
                rows: unstagedRows,
                emptyText: isFiltering ? String(localized: "No matches") : String(localized: "No unstaged changes"),
                allLabel: String(localized: "Stage all"),
                onAll: { Task { await viewModel.stage(unstaged) } },
                moveTitle: String(localized: "Stage"),
                side: .unstaged,
                onMove: { Task { await viewModel.stageSelected() } },
                lineCounts: viewModel.workingCopy.unstagedLineCounts
            )
            section(
                title: String(localized: "Staged"),
                files: staged,
                rows: stagedRows,
                emptyText: isFiltering ? String(localized: "No matches") : String(localized: "Nothing staged"),
                allLabel: String(localized: "Unstage all"),
                onAll: { Task { await viewModel.unstage(staged) } },
                moveTitle: String(localized: "Unstage"),
                side: .staged,
                onMove: { Task { await viewModel.unstageSelected() } },
                lineCounts: viewModel.workingCopy.stagedLineCounts
            )
            .padding(.top, Spacing.s12)
        }
    }

    @ViewBuilder
    private func section(title: String,
                         files: [WorkingCopyFile],
                         rows: [WorkingCopyRowID],
                         emptyText: String,
                         allLabel: String,
                         onAll: @escaping () -> Void,
                         moveTitle: String,
                         side: WorkingCopySide,
                         onMove: @escaping () -> Void,
                         lineCounts: [String: DiffStats]) -> some View {
        let ticked = viewModel.workingCopy.selectedFilePaths
        let selection = StagingSectionSelection(paths: files.map(\.path), selected: ticked)
        let tickedCount = selection.count(of: files.count)
        let batch = StagingRowBatch(
            count: tickedCount,
            move: onMove,
            stash: { stash(tickedFiles(in: files)) },
            discard: { pendingDiscard = tickedFiles(in: files) }
        )
        VStack(spacing: 0) {
            StagingFileSectionHeader(
                title: title,
                count: files.count,
                selection: selection,
                onToggleAll: { viewModel.workingCopy.setSelection(files, selected: selection != .full) },
                actionLabel: allLabel,
                onAction: onAll
            )
            if files.isEmpty {
                Text(emptyText)
                    .textRole(.callout)
                    .foregroundStyle(theme.colors.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Spacing.s8)
                    .frame(height: theme.density.metrics.rowList)
            } else {
                ForEach(files) { f in
                    let id = WorkingCopyRowID(side: side, path: f.path)
                    StagingRow(file: f, viewModel: viewModel, side: side, lineCounts: lineCounts[f.path],
                               onClick: { click($0, on: id, rows: rows) },
                               batch: tickedCount > 1 && ticked.contains(f.path) ? batch : nil)
                        .id(id)
                }
            }
            if selection != .empty {
                StagingBatchBar(
                    count: tickedCount,
                    moveTitle: moveTitle,
                    onMove: onMove,
                    onStash: batch.stash,
                    onDiscard: {
                        let files = tickedFiles(in: files)
                        Task {
                            await viewModel.discardChanges(files)
                            viewModel.workingCopy.deselect(files)
                        }
                    },
                    disabled: viewModel.isMutating
                )
            }
        }
    }

    // MARK: Clicks and keys

    private func click(_ kind: StagingRowClick, on id: WorkingCopyRowID, rows: [WorkingCopyRowID]) {
        switch kind {
        case .open: open(id)
        case .toggleTick: viewModel.workingCopy.toggleTick(id)
        case .extendTicks: viewModel.workingCopy.extendTicks(to: id, rows: rows)
        }
        listFocused = true
    }

    /// Opens `id`'s diff; the next Shift run starts there.
    private func open(_ id: WorkingCopyRowID) {
        viewModel.workingCopy.select(id, in: id.side == .staged ? staged : unstaged)
        viewModel.workingCopy.noteOpened(id)
    }

    /// The open row, when it's one of the listed (unfiltered) rows.
    private var openRow: WorkingCopyRowID? {
        viewModel.workingCopy.selectedRowID.flatMap { rowIDs.contains($0) ? $0 : nil }
    }

    /// Space: flips the open row's tick.
    private func tickOpenRow() -> KeyPress.Result {
        guard let openRow else { return .ignored }
        viewModel.workingCopy.toggleTick(openRow)
        return .handled
    }

    /// ⌘A: ticks the open row's section — Unstaged when no row is open.
    private func tickOpenSection() {
        let files = switch openRow?.side ?? (unstaged.isEmpty ? .staged : .unstaged) {
        case .staged: staged
        case .unstaged: unstaged
        }
        viewModel.workingCopy.setSelection(files, selected: true)
    }

    /// ⌘⌫: asks to discard every ticked file on screen, or the open one when
    /// none is ticked.
    private func discardTickedOrOpen() {
        guard !viewModel.isMutating else { return }
        var seen = Set<String>()
        var files = (unstaged + staged).filter {
            viewModel.workingCopy.selectedFilePaths.contains($0.path) && seen.insert($0.path).inserted
        }
        if files.isEmpty, let openRow, let open = (unstaged + staged).first(where: { $0.path == openRow.path }) {
            files = [open]
        }
        guard !files.isEmpty else { return }
        pendingDiscard = files
    }

    // MARK: Batch actions

    private func tickedFiles(in files: [WorkingCopyFile]) -> [WorkingCopyFile] {
        files.filter { viewModel.workingCopy.selectedFilePaths.contains($0.path) }
    }

    private func stash(_ files: [WorkingCopyFile]) {
        Task {
            if await viewModel.stash(files) {
                viewModel.workingCopy.deselect(files)
            }
        }
    }

    // MARK: Discard confirmation

    /// One file reads like the row's own dialog; several like the batch bar's.
    private var discardTitle: String {
        guard let files = pendingDiscard else { return "" }
        if files.count == 1, let file = files.first {
            let name = (file.path as NSString).lastPathComponent
            return file.isUntracked ? String(localized: "Delete \(name)?") : String(localized: "Discard changes to \(name)?")
        }
        return String(localized: "Discard changes to \(files.count) files?")
    }

    private func discardButtonTitle(_ files: [WorkingCopyFile]) -> String {
        if files.count == 1, let file = files.first {
            return file.isUntracked ? String(localized: "Delete file") : String(localized: "Discard changes")
        }
        return String(localized: "Discard")
    }

    private func discardMessage(_ files: [WorkingCopyFile]) -> String {
        if files.count == 1, let file = files.first {
            return file.isUntracked
                ? String(localized: "The file will be removed from disk. This can't be undone from the app.")
                : String(localized: "Local changes will be reverted to the last committed version. This can't be undone.")
        }
        return String(localized: "Local changes will be lost and untracked files deleted. This can't be undone.")
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    let vm: RepositoryViewModel = .preview
    StagingFilesColumn(
        viewModel: vm,
        staged: vm.workingCopy.status.stagedFiles,
        unstaged: vm.workingCopy.status.unstagedFiles,
        statusLoading: false
    )
    .frame(width: 440, height: 600)
    .background(theme.colors.bgContent)
    .appTheme(theme)
}
