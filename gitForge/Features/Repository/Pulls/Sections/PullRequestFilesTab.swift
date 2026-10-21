import SwiftUI

/// The PR's files over the selected one's diff, with its review threads:
/// under their lines, above the diff when they aren't on it, and in "Other
/// comments" when their file isn't in the list.
struct PullRequestFilesTab: View {
    let store: PullRequestStore

    /// The list id of "Other comments": no path can be empty.
    static let otherCommentsID = ""

    @Environment(\.appTheme) private var theme
    @State private var selectedPath: String?
    @State private var diffViewMode: DiffPane.ViewMode = .unified
    @FocusState private var listFocused: Bool

    private var files: [PullRequestFileChange] { store.files }
    private var hasOtherComments: Bool { !store.placedThreads.other.isEmpty }
    private var listIDs: [String] { (hasOtherComments ? [Self.otherCommentsID] : []) + files.map(\.path) }

    var body: some View {
        if files.isEmpty && !hasOtherComments {
            if store.isLoadingDetail {
                placeholderList
            } else {
                EmptyState(symbol: "square.and.pencil", title: String(localized: "No files changed"))
            }
        } else {
            // Files over the diff: next to the PR list the detail is too
            // narrow for two columns.
            VStack(spacing: 0) {
                fileList
                    .frame(height: fileListHeight)
                Rectangle().fill(theme.colors.separator).frame(height: 1)
                detailPane
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // The tab outlives a PR switch: the list comes back on another
            // PR's files, still holding the old path.
            .onAppear { selectedPath = Self.selection(keeping: selectedPath, ids: listIDs, files: files) }
            .onChange(of: listIDs) { _, ids in
                selectedPath = Self.selection(keeping: selectedPath, ids: ids, files: files)
            }
        }
    }

    /// Up to about seven rows, then it scrolls.
    private var fileListHeight: CGFloat {
        CGFloat(min(listIDs.count, 7)) * theme.density.metrics.rowFile + Spacing.s6 * 2
    }

    private var fileList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    if hasOtherComments {
                        PullRequestOtherCommentsRow(openThreads: store.placedThreads.otherOpenCount,
                                                    isSelected: selectedPath == Self.otherCommentsID,
                                                    onSelect: { select(Self.otherCommentsID) })
                            .id(Self.otherCommentsID)
                    }
                    ForEach(files) { file in
                        PullRequestFileRow(
                            file: file,
                            isSelected: file.path == selectedPath,
                            openThreads: store.placedThreads.openCount(for: file.path),
                            onSelect: { select(file.path) }
                        )
                        .id(file.path)
                    }
                }
                .padding(Spacing.s6)
            }
            .listKeyboardNavigation(
                ids: listIDs,
                selection: selectedPath,
                isFocused: $listFocused,
                scrollProxy: proxy
            ) { selectedPath = $0 }
        }
    }

    /// `current` while it's still listed; otherwise the first file, or
    /// "Other comments" when there's nothing else.
    static func selection(keeping current: String?, ids: [String], files: [PullRequestFileChange]) -> String? {
        if let current, ids.contains(current) { return current }
        return files.first?.path ?? ids.first
    }

    private func select(_ id: String) {
        selectedPath = id
        listFocused = true
    }

    private static let placeholderSamples: [PullRequestFileChange] = [
        .init(path: "Sources/Features/PullRequest/PullRequestDetailView.swift", oldPath: nil, status: .modified, additions: 10, deletions: 4, patch: nil),
        .init(path: "Sources/Core/Models/PullRequest.swift", oldPath: nil, status: .modified, additions: 10, deletions: 4, patch: nil),
        .init(path: "Sources/Core/RemoteHosting/GitHubProvider.swift", oldPath: nil, status: .modified, additions: 10, deletions: 4, patch: nil),
        .init(path: "Sources/Core/RemoteHosting/GitLabProvider.swift", oldPath: nil, status: .modified, additions: 10, deletions: 4, patch: nil),
        .init(path: "Sources/DesignSystem/Components/Skeleton.swift", oldPath: nil, status: .modified, additions: 10, deletions: 4, patch: nil),
        .init(path: "README.md", oldPath: nil, status: .modified, additions: 10, deletions: 4, patch: nil),
        .init(path: "Tests/PullRequestTests.swift", oldPath: nil, status: .modified, additions: 10, deletions: 4, patch: nil),
    ]

    private var placeholderList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Self.placeholderSamples) { file in
                    PullRequestFileRow(file: file, isSelected: false, onSelect: {})
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .skeleton(true)
    }

    // MARK: Detail

    @ViewBuilder
    private var detailPane: some View {
        VStack(spacing: 0) {
            if let error = store.threadsError {
                threadsErrorBar(error)
            }
            if selectedPath == Self.otherCommentsID {
                OtherCommentsList(store: store, threads: store.placedThreads.other)
            } else {
                let selected = files.first(where: { $0.path == selectedPath })
                if let selected, let fileLevel = store.placedThreads.fileLevel[selected.path], !fileLevel.isEmpty {
                    FileThreadsSection(store: store, threads: fileLevel)
                        .id(selected.path)
                }
                diffPane(selected)
            }
        }
    }

    /// The diff keeps showing when the threads can't load. While Retry
    /// works, the bar stays and says so.
    private func threadsErrorBar(_ error: String) -> some View {
        HStack(spacing: Spacing.s8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(theme.colors.warn)
            Text("Couldn't load comments")
                .textRole(.callout, weight: .semibold)
                .foregroundStyle(theme.colors.textPrimary)
            Spacer(minLength: 0)
            if store.isLoadingThreads {
                ProgressView().controlSize(.small)
            }
            GFButton(title: String(localized: "Retry"), size: .small, disabled: store.isLoadingThreads) {
                Task { await store.loadThreads() }
            }
        }
        .padding(.horizontal, Spacing.s12)
        .padding(.vertical, Spacing.s6)
        .background(theme.colors.warnSoft)
        .help(error)
    }

    private func diffPane(_ selected: PullRequestFileChange?) -> some View {
        let hunks: [DiffHunk] = {
            guard let patch = selected?.patch, !patch.isEmpty else { return [] }
            return DiffParser.parse(patch)
        }()
        return DiffPane(
            file: selected?.path,
            status: selected.map { StatusTag.Kind(pullRequestFile: $0.status) },
            hunks: hunks,
            lineAnnotations: selected.map(annotations(for:)),
            viewMode: $diffViewMode
        )
    }

    /// The file's threads under their lines, the open new-comment box with
    /// them, and the "+" on every hunk line. The content reads the store in
    /// its own views, so typing doesn't redraw the diff.
    private func annotations(for file: PullRequestFileChange) -> DiffLineAnnotations {
        var refs = Set(store.placedThreads.inline[file.path]?.keys.map { $0 } ?? [])
        if let target = store.composerTarget, target.path == file.path { refs.insert(target.ref) }
        let store = store
        return DiffLineAnnotations(
            refs: refs,
            content: { AnyView(DiffLineThreads(store: store, path: file.path, refs: $0)) },
            onAddComment: { line, side in
                store.composerTarget = CommentTarget.make(path: file.path, oldPath: file.oldPath, line: line, side: side)
            }
        )
    }
}

#Preview("Loaded") {
    @Previewable @State var theme = AppTheme()
    PullRequestFilesTab(store: .previewWithDetail)
        .previewAppState(.preview)
        .frame(width: 1200, height: 720)
        .background(theme.colors.bgElevated)
        .appTheme(theme)
}

#Preview("Threads") {
    @Previewable @State var theme = AppTheme()
    PullRequestFilesTab(store: .previewWithThreads)
        .previewAppState(.preview)
        .frame(width: 900, height: 720)
        .background(theme.colors.bgElevated)
        .appTheme(theme)
}

#Preview("Loading") {
    @Previewable @State var theme = AppTheme()
    PullRequestFilesTab(store: .previewLoadingDetail)
        .previewAppState(.preview)
        .frame(width: 1200, height: 720)
        .background(theme.colors.bgElevated)
        .appTheme(theme)
}
