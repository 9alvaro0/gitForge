import SwiftUI
import AppKit

/// Presents "Recover lost commits" for `WorkspaceUI.recoverCommitsVisible`.
/// Mounted once by `ContentRouter`, so the Repository menu and ⌘K open it
/// over whatever section is showing.
struct RecoverCommitsSheetModifier: ViewModifier {
    let viewModel: RepositoryViewModel

    @Environment(AppState.self) private var appState

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: Bindable(appState.ui).recoverCommitsVisible) {
                RecoverCommitsSheet(viewModel: viewModel)
                    // File history is a sheet too, presented under this one.
                    .environment(\.fileInspector, nil)
            }
    }
}

extension View {
    func recoverCommitsSheet(viewModel: RepositoryViewModel) -> some View {
        modifier(RecoverCommitsSheetModifier(viewModel: viewModel))
    }
}

/// HEAD's reflog (or one branch's), newest first and in words, with the
/// selected entry's commit, its files and diff, and three ways to get it
/// back: a branch on it, a checkout, or a reset of the current branch to it.
struct RecoverCommitsSheet: View {
    let viewModel: RepositoryViewModel

    @Environment(AppState.self) private var appState
    @Environment(\.appTheme) private var theme
    @Environment(\.appPreferences) private var preferences
    @Environment(\.dismiss) private var dismiss

    @State private var store: RecoverStore
    @State private var source: RecoverStore.Source = .head
    @State private var diffModeOverride: DiffPane.ViewMode?
    @FocusState private var listFocused: Bool

    @State private var branchSheet = false
    @State private var branchName = ""
    @State private var resetMode: GitCLI.ResetMode?
    /// What the last action did, said in the sheet too: the toast shows in
    /// the window under it.
    @State private var notice: ToastMessage?

    static let listWidth: CGFloat = 320

    init(viewModel: RepositoryViewModel) {
        self.viewModel = viewModel
        _store = State(initialValue: RecoverStore(cli: viewModel.cli))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            separator
            HStack(spacing: 0) {
                entryList
                    .frame(width: Self.listWidth)
                    .frame(maxHeight: .infinity)
                Rectangle().fill(theme.colors.separator).frame(width: 1)
                detailColumn
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 880, idealWidth: 1040, minHeight: 560, idealHeight: 680)
        .background(theme.colors.bgElevated)
        .task(id: source) {
            await store.load(source)
            listFocused = true
        }
        .sheet(isPresented: $branchSheet) {
            CommitBranchSheet(
                commitShortSha: store.selectedEntry?.commit.shortSha ?? "",
                name: $branchName,
                confirmTitle: String(localized: "Create branch"),
                onCancel: { branchSheet = false },
                onConfirm: { Task { await createBranch() } }
            )
        }
        .confirmationDialog(resetTitle, isPresented: resetConfirmBinding, titleVisibility: .visible) {
            Button(resetMode == .hard ? String(localized: "Reset (destructive)") : String(localized: "Reset"),
                   role: resetMode == .hard ? .destructive : nil) {
                if let mode = resetMode { Task { await reset(mode: mode) } }
            }
            Button("Cancel", role: .cancel) { resetMode = nil }
        } message: {
            Text(CommitActionsMenu.resetConfirmMessage(for: resetMode, shortSha: store.selectedEntry?.commit.shortSha ?? ""))
        }
    }

    private var separator: some View {
        Rectangle().fill(theme.colors.separator).frame(height: 1)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: Spacing.s12) {
            VStack(alignment: .leading, spacing: Spacing.s4) {
                Text("Recover lost commits")
                    .textRole(.headline)
                    .foregroundStyle(theme.colors.textPrimary)
                Text("Every move of \(sourceName), newest first. Commits a reset, an amend or a rebase left behind are still here.")
                    .textRole(.callout)
                    .foregroundStyle(theme.colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Spacing.s12)
            HStack(spacing: Spacing.s6) {
                Text("Reflog of")
                    .textRole(.callout)
                    .foregroundStyle(theme.colors.textTertiary)
                SettingsPicker(current: sourceName) {
                    Button("HEAD") { source = .head }
                    if !branchNames.isEmpty {
                        Divider()
                        ForEach(branchNames, id: \.self) { name in
                            Button(name) { source = .branch(name) }
                        }
                    }
                }
                .frame(width: 180)
                .help("Show what HEAD did, or the moves of one branch")
                .accessibilityLabel("Reflog of \(sourceName)")
            }
            GFButton(title: String(localized: "Done"), shortcut: .cancelAction) { dismiss() }
        }
        .padding(.horizontal, Spacing.s16)
        .padding(.vertical, Spacing.s12)
    }

    private var sourceName: String {
        switch source {
        case .head: "HEAD"
        case .branch(let name): name
        }
    }

    private var branchNames: [String] { viewModel.localBranches.map(\.name) }

    // MARK: Entries

    @ViewBuilder
    private var entryList: some View {
        if !store.hasLoaded {
            entrySkeleton
        } else if let error = store.loadError {
            EmptyState(symbol: "exclamationmark.triangle", title: String(localized: "Couldn’t read the reflog"),
                       subtitle: error)
                .padding(Spacing.s16)
        } else if store.entries.isEmpty {
            EmptyState(symbol: "clock.arrow.circlepath", title: String(localized: "Nothing recorded yet"),
                       subtitle: String(localized: "Git records each move here once there are commits."))
                .padding(Spacing.s16)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(store.entries) { entry in
                            RecoverEntryRow(
                                entry: entry,
                                lostCount: store.lostCount(of: entry),
                                isSelected: entry.id == store.selectedEntryId
                            ) {
                                listFocused = true
                                Task { await store.select(entry) }
                            }
                            .id(entry.id)
                        }
                    }
                    .padding(Spacing.s6)
                }
                .listKeyboardNavigation(
                    ids: store.entries.map(\.id),
                    selection: store.selectedEntryId,
                    isFocused: $listFocused,
                    scrollProxy: proxy
                ) { id in
                    guard let entry = store.entries.first(where: { $0.id == id }) else { return }
                    Task { await store.select(entry) }
                }
            }
        }
    }

    private var entrySkeleton: some View {
        VStack(spacing: 1) {
            ForEach(0..<6, id: \.self) { _ in
                RecoverEntryRow(entry: .placeholder, lostCount: nil, isSelected: false, onSelect: {})
            }
            Spacer(minLength: 0)
        }
        .padding(Spacing.s6)
        .skeleton(true)
        .accessibilityHidden(true)
    }

    // MARK: Detail

    @ViewBuilder
    private var detailColumn: some View {
        if let entry = store.selectedEntry {
            VStack(alignment: .leading, spacing: 0) {
                detailHeader(entry)
                    .padding(.horizontal, Spacing.s16)
                    .padding(.top, Spacing.s12)
                    .padding(.bottom, Spacing.s8)
                CommitFileList(
                    files: store.detail?.files,
                    repositoryURL: viewModel.repository.url,
                    selection: store.selectedFile
                ) { path in Task { await store.selectFile(path) } }
                .frame(height: fileListHeight)
                separator
                DiffPane(
                    file: store.selectedFile,
                    status: selectedFileStatus,
                    hunks: store.fileDiff,
                    loading: store.isLoadingFileDiff,
                    emptyState: store.fileDiffEmptyState,
                    onWhitespaceChange: { Task { await store.reloadFileDiff() } },
                    loadNewSide: store.selectedFile.map { _ -> () async -> [String]? in
                        { await store.newSideLines() }
                    },
                    viewMode: diffMode
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else if store.hasLoaded {
            EmptyState(symbol: "clock.arrow.circlepath", title: String(localized: "Select an entry"),
                       subtitle: String(localized: "Its commit and changes appear here."))
        } else {
            Color.clear
        }
    }

    private func detailHeader(_ entry: ReflogEntry) -> some View {
        let commit = entry.commit
        return VStack(alignment: .leading, spacing: Spacing.s8) {
            Text(entry.title)
                .textRole(.caption, weight: .semibold)
                .foregroundStyle(theme.colors.textTertiary)
            Text(commit.subject)
                .textRole(.title)
                .foregroundStyle(theme.colors.textPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .help(commit.subject)
            HStack(spacing: Spacing.s8) {
                AuthorAvatar(author: commit.author, sha: commit.sha, size: 22)
                    .accessibilityHidden(true)
                Text(commit.authorName)
                    .textRole(.callout, weight: .medium)
                    .foregroundStyle(theme.colors.textPrimary)
                    .lineLimit(1)
                    .help(commit.authorEmail)
                Text("·").foregroundStyle(theme.colors.textQuaternary)
                Text(preferences.dateDisplayMode.format(commit.authorDate))
                    .textRole(.callout)
                    .foregroundStyle(theme.colors.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: Spacing.s8)
                copyShaButton(commit)
            }
            if let lost = store.lostCount(of: entry) {
                LostCommitsLine(count: lost)
            }
            actions(entry)
            if let notice {
                NoticeLine(toast: notice)
            }
        }
    }

    private func copyShaButton(_ commit: Commit) -> some View {
        Button {
            NSPasteboard.general.declareTypes([.string], owner: nil)
            NSPasteboard.general.setString(commit.sha, forType: .string)
        } label: {
            HStack(spacing: Spacing.s4) {
                Text(commit.shortSha).textRole(.monoSmall)
                Image(systemName: "doc.on.doc").font(.system(size: 10)).accessibilityHidden(true)
            }
            .foregroundStyle(theme.colors.textSecondary)
            .padding(.horizontal, Spacing.s6)
            .frame(height: 22)
            .background(RoundedRectangle(cornerRadius: Radius.controlSmall).fill(theme.colors.fillControl))
        }
        .buttonStyle(.plain)
        .fixedSize()
        .help("Copy full SHA")
        .accessibilityLabel("Copy full SHA \(commit.shortSha)")
    }

    private func actions(_ entry: ReflogEntry) -> some View {
        let busy = viewModel.isMutating
        let shortSha = entry.commit.shortSha
        return HStack(spacing: Spacing.s8) {
            GFButton(title: String(localized: "Create branch here…"), systemImage: "arrow.triangle.branch",
                     style: .primary, disabled: busy) {
                notice = nil
                branchName = entry.suggestedBranchName(avoiding: Set(branchNames))
                branchSheet = true
            }
            .help("Create a branch at \(shortSha) so its commits are kept. HEAD stays where it is.")
            GFButton(title: String(localized: "Checkout (detached)"), systemImage: "arrow.right.circle", disabled: busy) {
                Task { await checkout(entry) }
            }
            .help("Check out \(shortSha) (detached HEAD) and go to History.")
            Menu {
                ForEach(GitCLI.ResetMode.allCases) { mode in
                    Button(mode.label) { resetMode = mode }
                }
            } label: {
                HStack(spacing: Spacing.s6) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 12, weight: .semibold))
                        .accessibilityHidden(true)
                    Text("Reset current branch here")
                        .textRole(.body, weight: .semibold)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(theme.colors.textTertiary)
                        .accessibilityHidden(true)
                }
                .lineLimit(1)
                .foregroundStyle(theme.colors.textPrimary)
                .padding(.horizontal, Spacing.s12)
                .frame(height: theme.density.metrics.buttonRegular)
                .background(RoundedRectangle(cornerRadius: Radius.control).fill(theme.colors.fillControl))
                .overlay(RoundedRectangle(cornerRadius: Radius.control).strokeBorder(theme.colors.strokeControl, lineWidth: 1))
                .contentShape(RoundedRectangle(cornerRadius: Radius.control))
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .disabled(busy)
            .help("Move \(currentBranchLabel) to \(shortSha). Soft / mixed / hard control how the working tree is affected — hard discards uncommitted changes.")
            Spacer(minLength: 0)
        }
    }

    private var currentBranchLabel: String {
        viewModel.currentBranchName ?? "HEAD"
    }

    /// Fits the files up to about six rows, then scrolls.
    private var fileListHeight: CGFloat {
        let rows = CGFloat(min(max(store.detail?.files.count ?? 3, 1), 6))
        return rows * theme.density.metrics.rowFile + Spacing.s24 + Spacing.s8
    }

    private var selectedFileStatus: StatusTag.Kind? {
        guard let path = store.selectedFile,
              let file = store.detail?.files.first(where: { $0.path == path }) else { return nil }
        return StatusTag.Kind(commitFile: file.status)
    }

    private var diffMode: Binding<DiffPane.ViewMode> {
        Binding(get: { diffModeOverride ?? preferences.defaultDiffMode },
                set: { diffModeOverride = $0 })
    }

    // MARK: Actions

    private var resetTitle: String {
        let sha = store.selectedEntry?.commit.shortSha ?? ""
        let branch = currentBranchLabel
        return String(localized: "Reset \(branch) to \(sha)?")
    }

    private var resetConfirmBinding: Binding<Bool> {
        Binding(get: { resetMode != nil }, set: { if !$0 { resetMode = nil } })
    }

    private func createBranch() async {
        guard let entry = store.selectedEntry else { return }
        let name = branchName.trimmingCharacters(in: .whitespaces)
        switch await viewModel.createBranch(name: name, startingAt: entry.commit.sha, checkout: false) {
        case .success:
            branchSheet = false
            let toast = ToastMessage(message: String(localized: "Created \(name) at \(entry.commit.shortSha)"), kind: .ok)
            notice = toast
            appState.ui.activeToast = toast
            await store.reload()
        case .failure(let error) where error is CancellationError:
            break
        case .failure(let error):
            // The sheet stays open so the name can be fixed and retried.
            appState.ui.activeToast = ToastMessage(message: error.userMessage, kind: .error)
            notice = ToastMessage(message: error.userMessage, kind: .error)
        }
    }

    /// Leaves the sheet for History first: a refusal over local changes is
    /// asked about by the window (`BlockedCheckoutPrompt`), under the sheet.
    private func checkout(_ entry: ReflogEntry) async {
        let sha = entry.commit.sha
        appState.ui.recoverCommitsVisible = false
        appState.ui.workspaceSection = .history
        let outcome = await viewModel.checkout(.commit(sha: sha))
        appState.ui.emitToast(for: outcome)
        if case .done = outcome {
            viewModel.history.selectedCommitId = sha
        }
    }

    private func reset(mode: GitCLI.ResetMode) async {
        guard let entry = store.selectedEntry else { return }
        resetMode = nil
        let shortSha = entry.commit.shortSha
        let outcome = await viewModel.reset(to: entry.commit.sha, mode: mode)
        appState.ui.emitToast(
            for: outcome,
            success: String(localized: "Reset \(mode.rawValue) to \(shortSha)"),
            conflicts: String(localized: "Reset has conflicts — resolve to continue"),
            undo: viewModel.undo.pending
        )
        switch outcome {
        case .clean:
            notice = ToastMessage(message: String(localized: "Reset \(mode.rawValue) to \(shortSha)"), kind: .ok)
            await store.reload()
        case .failed(let message):
            notice = ToastMessage(message: message, kind: .error)
        case .conflicts:
            appState.ui.recoverCommitsVisible = false
        case .cancelled:
            break
        }
    }
}

// MARK: - Rows

/// One reflog entry: what happened and when, then the commit it offers
/// (short SHA and subject), and whether recovering it brings commits back.
private struct RecoverEntryRow: View {
    let entry: ReflogEntry
    let lostCount: Int?
    let isSelected: Bool
    let onSelect: () -> Void

    @Environment(\.appTheme) private var theme
    @State private var hovering = false

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: Spacing.s2) {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.s8) {
                    Text(entry.title)
                        .textRole(.callout, weight: .semibold)
                        .foregroundStyle(theme.colors.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: Spacing.s4)
                    Text(DateDisplayMode.elapsed(since: entry.date))
                        .textRole(.caption)
                        .foregroundStyle(theme.colors.textTertiary)
                        .lineLimit(1)
                        .fixedSize()
                        .help(DateDisplayMode.absolute.format(entry.date))
                }
                HStack(spacing: Spacing.s6) {
                    Text(entry.commit.shortSha)
                        .textRole(.monoSmall)
                        .foregroundStyle(theme.colors.textSecondary)
                    Text(entry.commit.subject)
                        .textRole(.caption)
                        .foregroundStyle(theme.colors.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                if let lostCount, lostCount > 0 {
                    HStack(spacing: Spacing.s4) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 10))
                            .accessibilityHidden(true)
                        Text(LostCommitsLine.text(count: lostCount))
                            .textRole(.caption, weight: .medium)
                    }
                    .foregroundStyle(theme.colors.warn)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.s8)
            .padding(.vertical, Spacing.s6)
            .background(RoundedRectangle(cornerRadius: Radius.row).fill(rowFill))
            .contentShape(.rect(cornerRadius: Radius.row))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .help(entry.message)
    }

    private var rowFill: Color {
        if isSelected { return theme.colors.accentSoft }
        return hovering ? theme.colors.fillHover : .clear
    }
}

/// Whether the selected entry's commit is on a branch, and if not, how many
/// commits a branch on it would keep.
private struct LostCommitsLine: View {
    let count: Int

    @Environment(\.appTheme) private var theme

    static func text(count: Int) -> String {
        count == 1
            ? String(localized: "1 commit not on any branch")
            : String(localized: "\(count) commits not on any branch")
    }

    var body: some View {
        HStack(spacing: Spacing.s6) {
            Image(systemName: count > 0 ? "exclamationmark.circle.fill" : "checkmark.circle")
                .font(.system(size: 11))
                .accessibilityHidden(true)
            Text(count > 0 ? Self.text(count: count) : String(localized: "On a branch or tag already"))
                .textRole(.callout, weight: count > 0 ? .medium : nil)
        }
        .foregroundStyle(count > 0 ? theme.colors.warn : theme.colors.textTertiary)
    }
}

/// The outcome of the last action, under the buttons.
private struct NoticeLine: View {
    let toast: ToastMessage

    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: Spacing.s6) {
            Image(systemName: toast.kind == .error ? "xmark.octagon.fill" : "checkmark.circle.fill")
                .font(.system(size: 11))
                .accessibilityHidden(true)
            Text(toast.message)
                .textRole(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(toast.kind == .error ? theme.colors.del : theme.colors.ok)
        .accessibilityElement(children: .combine)
    }
}

private extension ReflogEntry {
    /// Filler for the skeleton while the reflog loads.
    static let placeholder = ReflogEntry(
        index: 0,
        movedTo: Commit(sha: String(repeating: "0", count: 40), parentShas: [], authorName: "", authorEmail: "",
                        authorDate: .now, subject: String(localized: "Loading commit…")),
        movedFrom: nil,
        date: .now,
        message: String(localized: "Loading commit…"),
        action: .other
    )
}

#Preview {
    @Previewable @State var theme = AppTheme()
    RecoverCommitsSheet(viewModel: .preview)
        .previewAppState(.preview)
        .appTheme(theme)
}
