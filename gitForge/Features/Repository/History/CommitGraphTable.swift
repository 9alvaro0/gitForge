import SwiftUI

/// Header + data table for the History view. Owns its own dual-axis ScrollView
/// so columns line up between header and rows even when the graph gutter is
/// wide enough to push the message off-screen — horizontal scroll engages
/// automatically. The header is pinned via a `LazyVStack` Section so it stays
/// at the top during vertical scroll and slides with content during horizontal
/// scroll (so the labels never desync from the columns below).
struct CommitGraphTable: View {
    let commits: [Commit]
    let layouts: [GraphRowLayout]
    let refsBySha: [String: [GitRef]]
    let currentBranch: String?
    let selectedSha: Commit.ID?
    let workingCopyDirty: Bool
    let columns: ResizableTableModel
    /// `nil` when search is inactive — every row renders at full opacity. When
    /// non-nil, non-matching rows dim so the graph topology stays intact (the
    /// lanes need both endpoints visible to make sense).
    var isMatch: ((Commit) -> Bool)? = nil
    let onSelect: (String) -> Void

    @Environment(\.appTheme) private var theme

    private var maxLanes: Int {
        layouts.map(\.totalLanes).max() ?? 1
    }
    private var rowHeight: CGFloat { theme.density.rowHeight }
    /// Grows with the number of simultaneously alive lanes so a wide history
    /// (e.g. many parallel `release/*` branches) doesn't get crammed into a
    /// fixed-width column. Floors at 110 to keep narrow histories looking the
    /// same as before.
    private var graphGutterWidth: CGFloat {
        let lanes = max(maxLanes, 1)
        let laneWidth: CGFloat = 14
        let leadingSpacer: CGFloat = 18
        let trailingPad: CGFloat = 8
        return max(110, leadingSpacer + CGFloat(lanes) * laneWidth + trailingPad)
    }

    private var totalFixedWidth: CGFloat {
        graphGutterWidth
            + columns.width("branchTag")
            + columns.width("author")
            + columns.width("sha")
            + columns.width("when")
            + (3 * 8)   // three drag handles between fixed columns
            + 36        // 18pt horizontal padding on each side
    }

    private static let minMessageWidth: CGFloat = 240

    var body: some View {
        GeometryReader { geo in
            let messageWidth = max(Self.minMessageWidth, geo.size.width - totalFixedWidth)
            let contentWidth = totalFixedWidth + messageWidth - 36 // padding accounted in HStack

            ScrollView([.vertical, .horizontal], showsIndicators: true) {
                LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                    Section {
                        if workingCopyDirty {
                            UncommittedRow(
                                rowHeight: rowHeight,
                                gutterWidth: graphGutterWidth,
                                columns: columns,
                                messageWidth: messageWidth
                            )
                        }
                        ForEach(Array(commits.enumerated()), id: \.element.sha) { idx, commit in
                            CommitRow(
                                commit: commit,
                                layout: layouts[safe: idx] ?? .empty,
                                maxLanes: maxLanes,
                                rowHeight: rowHeight,
                                gutterWidth: graphGutterWidth,
                                refs: refsBySha[commit.sha] ?? [],
                                currentBranch: currentBranch,
                                isSelected: commit.sha == selectedSha,
                                dimmed: isMatch.map { !$0(commit) } ?? false,
                                columns: columns,
                                messageWidth: messageWidth,
                                onSelect: { onSelect(commit.sha) }
                            )
                        }
                    } header: {
                        CommitTableHeader(
                            gutterWidth: graphGutterWidth,
                            columns: columns,
                            messageWidth: messageWidth
                        )
                    }
                }
                .frame(width: max(contentWidth + 36, geo.size.width), alignment: .leading)
            }
        }
    }
}

private struct CommitTableHeader: View {
    let gutterWidth: CGFloat
    let columns: ResizableTableModel
    let messageWidth: CGFloat

    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: 0) {
            Text("GRAPH").frame(width: gutterWidth, alignment: .leading)
            Text("BRANCH / TAG")
                .frame(width: columns.width("branchTag"), alignment: .leading)
            ColumnDragHandle(width: columns.binding(for: "branchTag"),
                             minWidth: columns.minWidth("branchTag"), maxWidth: 380,
                             onCommit: { columns.commit() })
            Text("MESSAGE").frame(width: messageWidth, alignment: .leading)
            Text("AUTHOR")
                .frame(width: columns.width("author"), alignment: .leading)
            ColumnDragHandle(width: columns.binding(for: "author"),
                             minWidth: columns.minWidth("author"), maxWidth: 220,
                             onCommit: { columns.commit() })
            Text("SHA")
                .frame(width: columns.width("sha"), alignment: .leading)
            ColumnDragHandle(width: columns.binding(for: "sha"),
                             minWidth: columns.minWidth("sha"), maxWidth: 140,
                             onCommit: { columns.commit() })
            Text("WHEN")
                .frame(width: columns.width("when"), alignment: .trailing)
        }
        .font(AppFont.mono(10.5, family: theme.monoFont))
        .tracking(0.6)
        .foregroundStyle(theme.palette.fg3)
        .padding(.horizontal, 18)
        .frame(height: 28)
        .background(theme.palette.bg1)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.palette.line).frame(height: 1) }
        .contextMenu {
            Button("Reset column widths") { columns.reset() }
        }
    }
}

private struct UncommittedRow: View {
    let rowHeight: CGFloat
    let gutterWidth: CGFloat
    let columns: ResizableTableModel
    let messageWidth: CGFloat

    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 0) {
                Spacer().frame(width: 18)
                Rectangle().fill(theme.palette.mod).frame(width: 8, height: 8)
                    .overlay(Rectangle().stroke(theme.palette.mod, lineWidth: 1))
            }
            .frame(width: gutterWidth, alignment: .leading)
            Color.clear.frame(width: columns.width("branchTag"))
            Color.clear.frame(width: 8)
            HStack(spacing: 8) {
                Circle().fill(theme.palette.mod).frame(width: 8, height: 8)
                Text("Uncommitted changes")
                    .font(AppFont.sans(12.5))
                    .italic()
                    .foregroundStyle(theme.palette.mod)
            }
            .frame(width: messageWidth, alignment: .leading)
            Color.clear.frame(width: columns.width("author"))
            Color.clear.frame(width: 8)
            Text("–")
                .font(AppFont.mono(11, family: theme.monoFont))
                .foregroundStyle(theme.palette.fg3)
                .frame(width: columns.width("sha"), alignment: .leading)
            Color.clear.frame(width: 8)
            Text("now")
                .font(AppFont.mono(11, family: theme.monoFont))
                .foregroundStyle(theme.palette.fg3)
                .frame(width: columns.width("when"), alignment: .trailing)
        }
        .padding(.horizontal, 18)
        .frame(height: rowHeight)
        .background(LinearGradient(colors: [theme.palette.mod.opacity(0.07), .clear], startPoint: .leading, endPoint: .trailing))
    }
}

private struct CommitRow: View {
    let commit: Commit
    let layout: GraphRowLayout
    let maxLanes: Int
    let rowHeight: CGFloat
    let gutterWidth: CGFloat
    let refs: [GitRef]
    let currentBranch: String?
    let isSelected: Bool
    let dimmed: Bool
    let columns: ResizableTableModel
    let messageWidth: CGFloat
    let onSelect: () -> Void

    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: 0) {
            graphGutter
                .frame(width: gutterWidth, alignment: .leading)
            branchTagColumn
                .frame(width: columns.width("branchTag"), alignment: .leading)
            Color.clear.frame(width: 8)
            messageColumn
                .frame(width: messageWidth, alignment: .leading)
            HStack(spacing: 6) {
                Avatar(name: commit.authorName, size: 16, colorSeed: commit.authorEmail)
                Text(commit.authorName)
                    .font(AppFont.sans(12))
                    .foregroundStyle(theme.palette.fg2)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(width: columns.width("author"), alignment: .leading)
            Color.clear.frame(width: 8)
            Text(commit.shortSha)
                .font(AppFont.mono(11, family: theme.monoFont))
                .foregroundStyle(theme.palette.fg3)
                .frame(width: columns.width("sha"), alignment: .leading)
            Color.clear.frame(width: 8)
            Text(relativeWhen)
                .font(AppFont.mono(11, family: theme.monoFont))
                .foregroundStyle(theme.palette.fg3)
                .frame(width: columns.width("when"), alignment: .trailing)
        }
        .padding(.horizontal, 18)
        .frame(height: rowHeight)
        .background(rowBackground)
        .overlay(alignment: .leading) {
            if isSelected { Rectangle().fill(theme.palette.accent).frame(width: 2) }
        }
        .opacity(dimmed ? 0.35 : 1)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }

    /// Re-uses the existing `GraphColumnView` so lane drawing matches the rest of the app.
    private var graphGutter: some View {
        HStack(spacing: 0) {
            Spacer().frame(width: 18)
            GraphColumnView(row: layout, maxLanes: max(maxLanes, 1))
        }
    }

    /// Up to 2 chips when refs ≤ 2, otherwise first chip + "+N" overflow pill.
    /// Refs are sorted so the current branch wins, then local, tag, remote.
    private var branchTagColumn: some View {
        HStack(spacing: 4) {
            ForEach(visibleRefs) { ref in
                BranchChip(
                    name: ref.displayName,
                    current: ref.isLocalBranch && ref.name == currentBranch,
                    remote: ref.isRemoteBranch,
                    tag: ref.isTag
                )
                .frame(maxWidth: 110, alignment: .leading)
            }
            if let extra = overflowCount {
                overflowPill(count: extra)
            }
            Spacer(minLength: 0)
        }
    }

    private var sortedRefs: [GitRef] {
        refs.sorted { a, b in
            let aCurrent = a.isLocalBranch && a.name == currentBranch
            let bCurrent = b.isLocalBranch && b.name == currentBranch
            if aCurrent != bCurrent { return aCurrent }
            let aWeight = Self.refWeight(a)
            let bWeight = Self.refWeight(b)
            if aWeight != bWeight { return aWeight < bWeight }
            return a.displayName < b.displayName
        }
    }

    private static func refWeight(_ ref: GitRef) -> Int {
        if ref.isLocalBranch  { return 0 }
        if ref.isTag          { return 1 }
        if ref.isRemoteBranch { return 2 }
        return 3
    }

    private var visibleRefs: [GitRef] {
        sortedRefs.count <= 2 ? sortedRefs : Array(sortedRefs.prefix(1))
    }

    private var overflowCount: Int? {
        sortedRefs.count > 2 ? sortedRefs.count - 1 : nil
    }

    @ViewBuilder
    private func overflowPill(count: Int) -> some View {
        Text("+\(count)")
            .font(AppFont.mono(10.5, family: theme.monoFont))
            .foregroundStyle(theme.palette.fg3)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: 10).fill(theme.palette.bg3))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(theme.palette.lineStrong, lineWidth: 1))
    }

    private var messageColumn: some View {
        Text(commit.subject)
            .font(AppFont.sans(12.5))
            .foregroundStyle(theme.palette.fg1)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var rowBackground: Color {
        if isSelected { return theme.palette.accentSoft }
        return .clear
    }

    private var relativeWhen: String {
        let f = RelativeDateTimeFormatter(); f.unitsStyle = .abbreviated
        return f.localizedString(for: commit.authorDate, relativeTo: .now)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    @Previewable @State var columns = ResizableTableModel(
        id: "history.preview",
        columns: [
            (id: "branchTag", defaultWidth: 220, minWidth: 80),
            (id: "author",    defaultWidth: 130, minWidth: 80),
            (id: "sha",       defaultWidth: 80,  minWidth: 60),
            (id: "when",      defaultWidth: 70,  minWidth: 50),
        ]
    )
    let vm = RepositoryViewModel.preview
    CommitGraphTable(
        commits: vm.commits,
        layouts: vm.graphLayouts,
        refsBySha: vm.refsBySha,
        currentBranch: vm.currentBranchName,
        selectedSha: vm.commits.first?.sha,
        workingCopyDirty: !vm.status.isClean,
        columns: columns,
        onSelect: { _ in }
    )
    .frame(width: 920, height: 480)
    .background(theme.palette.bg2)
    .appTheme(theme)
}
