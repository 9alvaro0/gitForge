import SwiftUI

/// `.gf-view-history` — orchestrates graph table + diff pane + commit detail.
struct HistoryView: View {
    @Bindable var viewModel: RepositoryViewModel
    @Environment(\.appTheme) private var theme

    enum HistoryFilter: Hashable { case all, local, remote, tags }
    @State private var filter: HistoryFilter = .all
    @State private var diffMode: DiffPane.ViewMode = .unified

    var body: some View {
        VStack(spacing: 0) {
            ContentHeader(title: "History") {
                MonoText("\(viewModel.currentBranchName ?? "—") · \(viewModel.commits.count) commits", dim: true)
            } right: {
                ToolButton(.fetch, label: "Fetch") { Task { await viewModel.fetch() } }
                ToolButton(.pull,  label: "Pull",  badge: viewModel.behindCount) { Task { await viewModel.pull() } }
                ToolButton(.push,  label: "Push",  badge: viewModel.aheadCount, primary: true) { Task { await viewModel.push() } }
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
            SegmentedControl<HistoryFilter>(
                [(.all, "All"), (.local, "Local"), (.remote, "Remote"), (.tags, "Tags")],
                selection: $filter
            )
            Spacer()
            HStack(spacing: 8) {
                MonoText("filter:", dim: true)
                ChipInput(text: "author:\(authorChipName)")
                IconButton(.plus, action: {})
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .background(theme.palette.bg2)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.palette.line).frame(height: 1) }
    }

    private var authorChipName: String {
        let raw = viewModel.commits.first?.authorName ?? "anyone"
        return raw.split(separator: " ").first.map(String.init) ?? raw
    }

    private var graphAndDiffColumn: some View {
        VStack(spacing: 0) {
            CommitTableHeader()
            CommitGraphTable(
                commits: viewModel.commits,
                layouts: viewModel.graphLayouts,
                refsBySha: viewModel.refsBySha,
                currentBranch: viewModel.currentBranchName,
                selectedSha: viewModel.selectedCommitId,
                workingCopyDirty: !viewModel.status.isClean
            ) { sha in
                viewModel.selectedCommitId = sha
                if let path = viewModel.detailCache[sha]?.files.first?.path {
                    viewModel.selectedCommitFile = path
                }
            }
            DiffPane(
                file: viewModel.selectedCommitFile,
                hunks: viewModel.commitFileDiff,
                loading: viewModel.loadingCommitFileDiff,
                viewMode: $diffMode
            )
            .frame(height: DesignTokens.Detail.diffPaneHeight)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

private struct CommitTableHeader: View {
    @Environment(\.appTheme) private var theme
    var body: some View {
        HStack(spacing: 0) {
            Text("GRAPH").frame(width: 110, alignment: .leading)
            Text("MESSAGE").frame(maxWidth: .infinity, alignment: .leading)
            Text("AUTHOR").frame(width: 130, alignment: .leading)
            Text("SHA").frame(width: 80, alignment: .leading)
            Text("WHEN").frame(width: 70, alignment: .trailing)
        }
        .font(AppFont.mono(10.5, family: theme.monoFont))
        .tracking(0.6)
        .foregroundStyle(theme.palette.fg3)
        .padding(.horizontal, 18)
        .padding(.vertical, 6)
        .background(theme.palette.bg1)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.palette.line).frame(height: 1) }
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    HistoryView(viewModel: RepositoryViewModel.preview)
        .frame(width: 1200, height: 720)
        .appTheme(theme)
}
