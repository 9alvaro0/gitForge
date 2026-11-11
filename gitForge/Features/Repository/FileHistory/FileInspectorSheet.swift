import SwiftUI
import AppKit

/// Presents the File history sheet for `WorkspaceUI.fileInspectorRequest`
/// and gives the section under it the action its file rows call. Mounted
/// once by `ContentRouter`, so every file row and ⌘K open it over whatever
/// section is showing.
struct FileInspectorSheetModifier: ViewModifier {
    let viewModel: RepositoryViewModel

    @Environment(AppState.self) private var appState

    func body(content: Content) -> some View {
        let ui = appState.ui
        content
            .environment(\.fileInspector, FileInspectorAction { ui.fileInspectorRequest = $0 })
            .sheet(item: Bindable(ui).fileInspectorRequest) { request in
                FileInspectorSheet(viewModel: viewModel, request: request)
            }
    }
}

extension View {
    func fileInspectorSheet(viewModel: RepositoryViewModel) -> some View {
        modifier(FileInspectorSheetModifier(viewModel: viewModel))
    }
}

/// One file's history on HEAD, newest first and across renames, with the
/// selected commit's diff of that file alone and a way to open the commit
/// in History.
struct FileInspectorSheet: View {
    let viewModel: RepositoryViewModel
    let request: FileInspectorRequest

    @Environment(AppState.self) private var appState
    @Environment(\.appTheme) private var theme
    @Environment(\.appPreferences) private var preferences
    @Environment(\.dismiss) private var dismiss

    @State private var history: FileHistoryStore
    @State private var diffModeOverride: DiffPane.ViewMode?
    @FocusState private var listFocused: Bool

    static let listWidth: CGFloat = 340

    init(viewModel: RepositoryViewModel, request: FileInspectorRequest) {
        self.viewModel = viewModel
        self.request = request
        _history = State(initialValue: FileHistoryStore(cli: viewModel.cli, path: request.path))
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
        .frame(minWidth: 880, idealWidth: 1080, minHeight: 560, idealHeight: 700)
        .background(theme.colors.bgElevated)
        .task {
            await history.load(selecting: request.revision)
            listFocused = true
        }
    }

    private var separator: some View {
        Rectangle().fill(theme.colors.separator).frame(height: 1)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: Spacing.s12) {
            VStack(alignment: .leading, spacing: Spacing.s4) {
                Text("File history")
                    .textRole(.headline)
                    .foregroundStyle(theme.colors.textPrimary)
                FilePathText(path: request.path)
                    .textRole(.mono)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .textSelection(.enabled)
                    .help(request.path)
                if let renames = renamesLine {
                    Text(renames)
                        .textRole(.caption)
                        .foregroundStyle(theme.colors.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: Spacing.s12)
            GFButton(title: String(localized: "Done"), shortcut: .cancelAction) { dismiss() }
        }
        .padding(.horizontal, Spacing.s16)
        .padding(.vertical, Spacing.s12)
    }

    /// "Previously old/name.swift, older/name.swift": the names the loaded
    /// history went through, newest first.
    private var renamesLine: String? {
        let names = history.renames.compactMap(\.previousPath)
        guard !names.isEmpty else { return nil }
        return String(localized: "Previously \(names.joined(separator: ", "))")
    }

    // MARK: Entries

    @ViewBuilder
    private var entryList: some View {
        if !history.hasLoaded {
            entrySkeleton
        } else if let error = history.loadError, history.entries.isEmpty {
            EmptyState(symbol: "exclamationmark.triangle", title: String(localized: "Couldn’t read the history"),
                       subtitle: error)
                .padding(Spacing.s16)
        } else if history.entries.isEmpty {
            EmptyState(symbol: "clock", title: String(localized: "No history on this branch"),
                       subtitle: String(localized: "No commit on HEAD touched this file. A new file has history once it’s committed."))
                .padding(Spacing.s16)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(history.entries) { entry in
                            FileHistoryRow(entry: entry, isSelected: entry.id == history.selectedEntryId) {
                                listFocused = true
                                Task { await history.select(entry) }
                            }
                            .id(entry.id)
                            .onAppear {
                                Task { await history.loadMoreIfNeeded(after: entry) }
                            }
                        }
                        if history.isLoadingMore {
                            ProgressView()
                                .controlSize(.small)
                                .padding(Spacing.s8)
                        }
                    }
                    .padding(Spacing.s6)
                }
                .listKeyboardNavigation(
                    ids: history.entries.map(\.id),
                    selection: history.selectedEntryId,
                    isFocused: $listFocused,
                    scrollProxy: proxy
                ) { id in
                    guard let entry = history.entries.first(where: { $0.id == id }) else { return }
                    Task { await history.select(entry) }
                }
                .onAppear {
                    if let id = history.selectedEntryId { proxy.scrollTo(id, anchor: .center) }
                }
            }
        }
    }

    private var entrySkeleton: some View {
        VStack(spacing: 1) {
            ForEach(0..<6, id: \.self) { _ in
                FileHistoryRow(entry: .placeholder, isSelected: false, onSelect: {})
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
        if let entry = history.selectedEntry {
            VStack(alignment: .leading, spacing: 0) {
                detailHeader(entry)
                    .padding(.horizontal, Spacing.s16)
                    .padding(.top, Spacing.s12)
                    .padding(.bottom, Spacing.s12)
                separator
                DiffPane(
                    file: entry.path,
                    status: entry.status.map { StatusTag.Kind(commitFile: $0) },
                    hunks: history.fileDiff,
                    loading: history.isLoadingFileDiff,
                    emptyState: history.fileDiffEmptyState,
                    onWhitespaceChange: { Task { await history.reloadFileDiff() } },
                    loadNewSide: entry.isDeletion ? nil : { () async -> [String]? in await history.newSideLines() },
                    viewMode: diffMode
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else if history.hasLoaded, !history.entries.isEmpty {
            EmptyState(symbol: "clock", title: String(localized: "Select a commit"),
                       subtitle: String(localized: "Its changes to this file appear here."))
        } else {
            Color.clear
        }
    }

    private func detailHeader(_ entry: FileHistoryEntry) -> some View {
        let commit = entry.commit
        return VStack(alignment: .leading, spacing: Spacing.s8) {
            Text(commit.subject)
                .textRole(.title)
                .foregroundStyle(theme.colors.textPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .help(commit.subject)
            HStack(spacing: Spacing.s8) {
                Avatar(name: commit.authorName, size: 22, colorSeed: commit.authorEmail)
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
                CopyShaButton(commit: commit)
            }
            HStack(spacing: Spacing.s8) {
                GFButton(title: String(localized: "Open in History"), systemImage: "arrow.right.circle") {
                    openInHistory(commit.sha)
                }
                .help("Close this and select \(commit.shortSha) in History")
                Spacer(minLength: 0)
            }
        }
    }

    private var diffMode: Binding<DiffPane.ViewMode> {
        Binding(get: { diffModeOverride ?? preferences.defaultDiffMode },
                set: { diffModeOverride = $0 })
    }

    // MARK: Actions

    /// Closes the sheet and selects `sha` in History, loading pages of the
    /// log until it's there.
    private func openInHistory(_ sha: String) {
        let ui = appState.ui
        let history = viewModel.history
        ui.fileInspectorRequest = nil
        ui.workspaceSection = .history
        Task {
            guard await !history.revealCommit(sha) else { return }
            ui.activeToast = ToastMessage(message: String(localized: "That commit isn’t in the history shown"), kind: .warn)
        }
    }
}

// MARK: - Pieces

/// A path with its folder dimmed and its name bright: the name is what
/// the eye scans. The caller sets the type role.
struct FilePathText: View {
    let path: String

    @Environment(\.appTheme) private var theme

    var body: some View {
        let folder = (path as NSString).deletingLastPathComponent
        let name = (path as NSString).lastPathComponent
        let prefix = folder.isEmpty ? "" : folder + "/"
        Text("\(Text(prefix).foregroundStyle(theme.colors.textTertiary))\(Text(name).foregroundStyle(theme.colors.textPrimary))")
    }
}

/// The short SHA as a button that copies the full one.
struct CopyShaButton: View {
    let commit: Commit

    @Environment(\.appTheme) private var theme

    var body: some View {
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
}

/// One commit of the file's history: what it did to the file, its subject
/// and when, then its short SHA and author, and the old name on a rename.
private struct FileHistoryRow: View {
    let entry: FileHistoryEntry
    let isSelected: Bool
    let onSelect: () -> Void

    @Environment(\.appTheme) private var theme
    @State private var hovering = false

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s8) {
                if let status = entry.status {
                    StatusTag(kind: StatusTag.Kind(commitFile: status))
                } else {
                    StatusTag(kind: .modified).hidden()
                }
                VStack(alignment: .leading, spacing: Spacing.s2) {
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.s8) {
                        Text(entry.commit.subject)
                            .textRole(.callout, weight: .semibold)
                            .foregroundStyle(theme.colors.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: Spacing.s4)
                        Text(DateDisplayMode.elapsed(since: entry.commit.authorDate))
                            .textRole(.caption)
                            .foregroundStyle(theme.colors.textTertiary)
                            .lineLimit(1)
                            .fixedSize()
                            .help(DateDisplayMode.absolute.format(entry.commit.authorDate))
                    }
                    HStack(spacing: Spacing.s6) {
                        Text(entry.commit.shortSha)
                            .textRole(.monoSmall)
                            .foregroundStyle(theme.colors.textSecondary)
                        Text(entry.commit.authorName)
                            .textRole(.caption)
                            .foregroundStyle(theme.colors.textSecondary)
                            .lineLimit(1)
                    }
                    if let from = entry.previousPath {
                        Text(renameNote(from: from))
                            .textRole(.caption)
                            .foregroundStyle(theme.colors.textTertiary)
                            .lineLimit(1)
                            .truncationMode(.head)
                            .help(from)
                    }
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
    }

    private func renameNote(from: String) -> String {
        if case .copied = entry.status { return String(localized: "Copied from \(from)") }
        return String(localized: "Renamed from \(from)")
    }

    private var rowFill: Color {
        if isSelected { return theme.colors.accentSoft }
        return hovering ? theme.colors.fillHover : .clear
    }
}

private extension FileHistoryEntry {
    /// Filler for the skeleton while the history loads.
    static let placeholder = FileHistoryEntry(
        commit: Commit(sha: String(repeating: "0", count: 40), parentShas: [], authorName: "",
                       authorEmail: "", authorDate: .now, subject: String(localized: "Loading commit…")),
        path: "",
        status: .modified
    )
}

#Preview {
    @Previewable @State var theme = AppTheme()
    FileInspectorSheet(viewModel: .preview, request: FileInspectorRequest(path: "src/App.swift"))
        .previewAppState(.preview)
        .appTheme(theme)
}
