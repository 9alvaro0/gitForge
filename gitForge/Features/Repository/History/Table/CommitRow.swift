import SwiftUI
import AppKit

struct CommitRow: View {
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
    let onSelect: () -> Void
    let onDoubleClick: () -> Void
    let onBranchDrop: ((DraggedBranch, BranchDropContext) -> Void)?
    /// `nil` disables the click-to-filter affordance on the author cell.
    var onFilterByAuthor: ((String) -> Void)? = nil

    @Environment(\.appTheme) private var theme
    @State private var rowDropTargeted = false

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.none) {
            graphGutter
                .frame(width: gutterWidth, alignment: .leading)
            Color.clear.frame(width: DesignTokens.Spacing.md)
            CommitRowChips(
                commitSha: commit.sha,
                refs: refs,
                currentBranch: currentBranch,
                onBranchDrop: onBranchDrop
            )
            .frame(width: columns.width("branchTag"), alignment: .leading)
            Color.clear.frame(width: DesignTokens.Spacing.md)
            Text(commit.subject)
                .font(AppFont.sans(12.5))
                .foregroundStyle(theme.palette.fg1)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: columns.width("message"), alignment: .leading)
            Color.clear.frame(width: DesignTokens.Spacing.md)
            authorCell
                .frame(width: columns.width("author"), alignment: .leading)
            Color.clear.frame(width: DesignTokens.Spacing.md)
            Text(commit.shortSha)
                .font(AppFont.mono(11, family: theme.monoFont))
                .foregroundStyle(theme.palette.fg3)
                .frame(width: columns.width("sha"), alignment: .leading)
            Color.clear.frame(width: DesignTokens.Spacing.md)
            Text(theme.dateDisplayMode.format(commit.authorDate))
                .font(AppFont.mono(11, family: theme.monoFont))
                .foregroundStyle(theme.palette.fg3)
                .frame(width: columns.width("when"), alignment: .trailing)
            Color.clear.frame(width: DesignTokens.Spacing.md)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DesignTokens.Spacing.xxxxl)
        .frame(height: rowHeight)
        .background(rowBackground)
        .overlay(alignment: .leading) {
            if isSelected { Rectangle().fill(theme.palette.accent).frame(width: 2) }
        }
        .opacity(dimmed ? 0.35 : 1)
        .contentShape(.rect)
        .onTapGesture(count: 2, perform: onDoubleClick)
        .onTapGesture(perform: onSelect)
        .modifier(RowDropModifier(
            enabled: onBranchDrop != nil,
            targetSha: commit.sha,
            isTargeted: $rowDropTargeted,
            onDrop: { dropped in
                onBranchDrop?(dropped, .onCommit(targetSha: commit.sha))
            }
        ))
        .contextMenu {
            Button("Copy SHA")        { copy(commit.sha) }
            Button("Copy short SHA")  { copy(commit.shortSha) }
            Button("Copy subject")    { copy(commit.subject) }
            Divider()
            Button("Copy author name")  { copy(commit.authorName) }
            Button("Copy author email") { copy(commit.authorEmail) }
            if let onFilterByAuthor {
                Divider()
                Button("Filter by \(commit.authorName)") {
                    onFilterByAuthor(commit.authorName)
                }
            }
        }
    }

    /// Author column. When the host wires `onFilterByAuthor`, clicking the
    /// cell prefills the History search with the author's name — common
    /// shortcut to scope the log to one person without typing.
    @ViewBuilder
    private var authorCell: some View {
        let row = HStack(spacing: DesignTokens.Spacing.sm) {
            Avatar(name: commit.authorName, size: 16, colorSeed: commit.authorEmail)
            Text(commit.authorName)
                .font(AppFont.sans(12))
                .foregroundStyle(theme.palette.fg2)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        if let onFilterByAuthor {
            Button {
                onFilterByAuthor(commit.authorName)
            } label: {
                row.contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help("Filter history by \(commit.authorName)")
        } else {
            row
        }
    }

    private func copy(_ string: String) {
        NSPasteboard.general.declareTypes([.string], owner: nil)
        NSPasteboard.general.setString(string, forType: .string)
    }

    /// Re-uses the existing `GraphColumnView` so lane drawing matches the
    /// rest of the app.
    private var graphGutter: some View {
        HStack(spacing: DesignTokens.Spacing.none) {
            Spacer().frame(width: DesignTokens.IconSize.xl)
            GraphColumnView(row: layout, maxLanes: max(maxLanes, 1))
        }
    }

    private var rowBackground: Color {
        if rowDropTargeted { return theme.palette.accent.opacity(DesignTokens.Opacity.subtle) }
        if isSelected { return theme.palette.accentSoft }
        return .clear
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    @Previewable @State var columns = ResizableTableModel(
        id: "history.row.preview",
        columns: [
            (id: "graph",     defaultWidth: 110, minWidth: 80),
            (id: "branchTag", defaultWidth: 220, minWidth: 80),
            (id: "message",   defaultWidth: 480, minWidth: 240),
            (id: "author",    defaultWidth: 130, minWidth: 80),
            (id: "sha",       defaultWidth: 80,  minWidth: 60),
            (id: "when",      defaultWidth: 70,  minWidth: 50),
        ]
    )
    let commit = Commit.previewSamples[0]
    VStack(spacing: 0) {
        CommitRow(
            commit: commit,
            layout: [GraphRowLayout].previewSamples[1],
            maxLanes: 2,
            rowHeight: 36,
            gutterWidth: 110,
            refs: GitRef.previewSamples,
            currentBranch: "main",
            isSelected: true,
            dimmed: false,
            columns: columns,
            onSelect: {}, onDoubleClick: {}, onBranchDrop: nil
        )
        CommitRow(
            commit: Commit.previewSamples[1],
            layout: [GraphRowLayout].previewSamples[2],
            maxLanes: 2,
            rowHeight: 36,
            gutterWidth: 110,
            refs: [],
            currentBranch: "main",
            isSelected: false,
            dimmed: false,
            columns: columns,
            onSelect: {}, onDoubleClick: {}, onBranchDrop: nil
        )
        CommitRow(
            commit: Commit.previewSamples[2],
            layout: [GraphRowLayout].previewSamples[3],
            maxLanes: 2,
            rowHeight: 36,
            gutterWidth: 110,
            refs: [],
            currentBranch: "main",
            isSelected: false,
            dimmed: true,
            columns: columns,
            onSelect: {}, onDoubleClick: {}, onBranchDrop: nil
        )
    }
    .frame(width: 1100)
    .background(theme.palette.bg2)
    .appTheme(theme)
}
