import SwiftUI

/// `.gf-view-history` — orchestrates graph table + diff pane + commit detail.
struct HistoryView: View {
    @Bindable var viewModel: RepositoryViewModel
    @Environment(\.appTheme) private var theme

    @State private var search: String = ""
    @State private var diffMode: DiffPane.ViewMode = .unified
    @State private var columns = ResizableTableModel(
        id: "history",
        columns: [
            (id: "branchTag", defaultWidth: 220, minWidth: 80),
            (id: "message",   defaultWidth: 480, minWidth: 240),
            (id: "author",    defaultWidth: 130, minWidth: 80),
            (id: "sha",       defaultWidth: 80,  minWidth: 60),
            (id: "when",      defaultWidth: 70,  minWidth: 50),
        ]
    )

    private static let diffHeightKey = "gitForge.history.diffPaneHeight"
    private static let collapsedThreshold: CGFloat = 80
    private static let defaultDiffHeight: CGFloat = 280

    @State private var diffPaneHeightValue: CGFloat = {
        let stored = UserDefaults.standard.double(forKey: HistoryView.diffHeightKey)
        return stored > 0 ? CGFloat(stored) : 280
    }()

    private var diffPaneHeight: Binding<CGFloat> {
        Binding(
            get: { diffPaneHeightValue },
            set: { diffPaneHeightValue = $0 }
        )
    }

    private func persistDiffPaneHeight() {
        UserDefaults.standard.set(Double(diffPaneHeightValue), forKey: Self.diffHeightKey)
    }

    var body: some View {
        VStack(spacing: 0) {
            ContentHeader(title: "History") {
                MonoText("\(viewModel.currentBranchName ?? "—") · \(viewModel.commits.count) commits", dim: true)
            } right: {
                ToolButton(.fetch, label: "Fetch") { Task { await viewModel.fetch() } }
                pullMenu
                pushMenu
            }
            filtersBar
            HStack(spacing: 0) {
                graphAndDiffColumn
                detailColumn
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.palette.bg2)
    }

    private var filtersBar: some View {
        HStack(spacing: 10) {
            GFTextField(placeholder: "Search subject, author, sha…", text: $search)
                .frame(maxWidth: 320)
            Spacer()
            MonoText(matchSummary, dim: true)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .background(theme.palette.bg2)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.palette.line).frame(height: 1) }
    }

    private var refsBySha: [String: [GitRef]] {
        Dictionary(grouping: viewModel.refs) { $0.targetSha }
    }

    private var trimmedQuery: String {
        search.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var matchSummary: String {
        guard !trimmedQuery.isEmpty else { return "\(viewModel.commits.count) commits" }
        let count = viewModel.commits.lazy.filter { commitMatches($0, query: trimmedQuery) }.count
        return "\(count) of \(viewModel.commits.count) match"
    }

    private func commitMatches(_ commit: Commit, query: String) -> Bool {
        let q = query.lowercased()
        return commit.subject.lowercased().contains(q)
            || commit.authorName.lowercased().contains(q)
            || commit.authorEmail.lowercased().contains(q)
            || commit.sha.lowercased().hasPrefix(q)
    }

    /// Closure passed to the table — `nil` when search is empty so every row
    /// renders at full opacity.
    private var searchMatcher: ((Commit) -> Bool)? {
        let query = trimmedQuery
        guard !query.isEmpty else { return nil }
        return { commitMatches($0, query: query) }
    }

    @ViewBuilder
    private var pullMenu: some View {
        Menu {
            Button("Pull (merge)")  { Task { await viewModel.pull(rebase: false) } }
            Button("Pull --rebase") { Task { await viewModel.pull(rebase: true)  } }
        } label: {
            HStack(spacing: 6) {
                GFIcon(kind: .pull, size: 14, stroke: theme.palette.fg2)
                Text("Pull").font(AppFont.sans(12))
                if viewModel.behindCount > 0 {
                    Text("\(viewModel.behindCount)")
                        .font(AppFont.mono(10, family: theme.monoFont))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: 3).fill(theme.palette.bg2))
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .foregroundStyle(theme.palette.fg2)
            .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).fill(theme.palette.bg3))
            .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).stroke(theme.palette.line, lineWidth: 1))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    @ViewBuilder
    private var pushMenu: some View {
        Menu {
            Button("Push") { Task { await viewModel.push() } }
            Button("Push --force-with-lease", role: .destructive) {
                Task { await viewModel.push(forceWithLease: true) }
            }
        } label: {
            HStack(spacing: 6) {
                GFIcon(kind: .push, size: 14, stroke: theme.palette.accentFg)
                Text("Push").font(AppFont.sans(12))
                if viewModel.aheadCount > 0 {
                    Text("\(viewModel.aheadCount)")
                        .font(AppFont.mono(10, family: theme.monoFont))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.22)))
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .foregroundStyle(theme.palette.accentFg)
            .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).fill(theme.palette.accent))
            .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).stroke(theme.palette.accent, lineWidth: 1))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private var graphAndDiffColumn: some View {
        VStack(spacing: 0) {
            CommitGraphTable(
                commits: viewModel.commits,
                layouts: viewModel.graphLayouts,
                refsBySha: refsBySha,
                currentBranch: viewModel.currentBranchName,
                selectedSha: viewModel.selectedCommitId,
                workingCopyDirty: !viewModel.status.isClean,
                columns: columns,
                isMatch: searchMatcher
            ) { sha in
                viewModel.selectedCommitId = sha
                if let path = viewModel.detailCache[sha]?.files.first?.path {
                    viewModel.selectedCommitFile = path
                }
            }
            .frame(maxHeight: .infinity)
            RowDragHandle(
                height: diffPaneHeight,
                minHeight: 36,
                maxHeight: 800,
                onCommit: { persistDiffPaneHeight() }
            )
            DiffPane(
                file: viewModel.selectedCommitFile,
                hunks: viewModel.commitFileDiff,
                loading: viewModel.loadingCommitFileDiff,
                viewMode: $diffMode
            )
            .frame(height: diffPaneHeight.wrappedValue)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: viewModel.selectedCommitFile) { _, newFile in
            guard newFile != nil, diffPaneHeight.wrappedValue < Self.collapsedThreshold else { return }
            withAnimation(.easeOut(duration: 0.18)) {
                diffPaneHeight.wrappedValue = Self.defaultDiffHeight
            }
        }
    }

    private var detailColumn: some View {
        Group {
            if let commit = viewModel.selectedCommit {
                ScrollView {
                    CommitDetailColumn(commit: commit, viewModel: viewModel)
                        .padding(18)
                }
            } else {
                EmptyState(icon: .diamond, title: "Select a commit",
                           subtitle: "Detail appears here.") { EmptyView() }
            }
        }
        .frame(width: DesignTokens.Detail.panelWidth)
        .background(theme.palette.bg1)
        .overlay(alignment: .leading) { Rectangle().fill(theme.palette.lineStrong).frame(width: 1) }
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    HistoryView(viewModel: RepositoryViewModel.preview)
        .frame(width: 1200, height: 720)
        .appTheme(theme)
}
