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
            SegmentedControl<HistoryFilter>(
                [(.all, "All"), (.local, "Local"), (.remote, "Remote"), (.tags, "Tags")],
                selection: $filter
            )
            Spacer()
            MonoText(refCountLabel, dim: true)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .background(theme.palette.bg2)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.palette.line).frame(height: 1) }
    }

    /// Refs to actually render as chips on commit rows for the selected filter.
    private var filteredRefsBySha: [String: [GitRef]] {
        let kept = viewModel.refs.filter { ref in
            switch filter {
            case .all:    return true
            case .local:  return ref.isLocalBranch
            case .remote: return ref.isRemoteBranch
            case .tags:   return ref.isTag
            }
        }
        return Dictionary(grouping: kept) { $0.targetSha }
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

    private var refCountLabel: String {
        let count = filteredRefsBySha.values.reduce(0) { $0 + $1.count }
        switch filter {
        case .all:    return "\(count) refs"
        case .local:  return "\(count) local branches"
        case .remote: return "\(count) remote branches"
        case .tags:   return "\(count) tags"
        }
    }

    private var graphAndDiffColumn: some View {
        VStack(spacing: 0) {
            CommitTableHeader()
            CommitGraphTable(
                commits: viewModel.commits,
                layouts: viewModel.graphLayouts,
                refsBySha: filteredRefsBySha,
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
