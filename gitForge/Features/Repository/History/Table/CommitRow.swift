import SwiftUI
import AppKit

struct CommitRow: View {
    let commit: Commit
    let layout: GraphRowLayout
    let maxLanes: Int
    let rowHeight: CGFloat
    let tableLayout: HistoryTableLayout
    let refs: [GitRef]
    let currentBranch: String?
    let isSelected: Bool
    var graphStyle = GraphStyle()
    var isHeadCommit = false
    let dimmed: Bool
    let onSelect: () -> Void
    let onDoubleClick: () -> Void
    let onBranchDrop: ((DraggedBranch, BranchDropContext) -> Void)?
    /// `nil` disables the click-to-filter affordance on the author cell.
    var onFilterByAuthor: ((String) -> Void)? = nil

    @Environment(\.appTheme) private var theme
    @Environment(\.appPreferences) private var preferences
    @State private var rowDropTargeted = false
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 0) {
            graphGutter
                .frame(width: tableLayout.graph, alignment: .leading)
            gap
            HStack(spacing: Spacing.s6) {
                CommitRowChips(
                    commitSha: commit.sha,
                    refs: refs,
                    currentBranch: currentBranch,
                    onBranchDrop: onBranchDrop,
                    // Chips may take up to ~40 % of Description; tight rows
                    // show one chip and "+N".
                    maxNameWidth: min(160, tableLayout.description * 0.3),
                    maxVisible: tableLayout.description < 360 ? 1 : 2
                )
                .fixedSize()
                Text(commit.subject)
                    .textRole(.body, weight: isSelected ? .medium : .regular)
                    .foregroundStyle(theme.colors.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(width: tableLayout.description, alignment: .leading)
            .clipped()
            gap
            if tableLayout.showsAuthor {
                authorCell
                    .frame(width: tableLayout.author, alignment: .leading)
                gap
            }
            Text(preferences.dateDisplayMode.format(commit.authorDate))
                .textRole(.callout)
                .monospacedDigit()
                .foregroundStyle(theme.colors.textTertiary)
                .lineLimit(1)
                .frame(width: tableLayout.date, alignment: .leading)
            gap
            Text(commit.shortSha)
                .textRole(.monoSmall)
                .foregroundStyle(theme.colors.textTertiary)
                .frame(width: tableLayout.commit, alignment: .trailing)
            Spacer(minLength: 0)
        }
        .padding(.leading, HistoryTableLayout.leadingPadding)
        .padding(.trailing, HistoryTableLayout.trailingPadding)
        .frame(height: rowHeight)
        .background(RoundedRectangle(cornerRadius: Radius.row).fill(rowBackground))
        .padding(.horizontal, HistoryTableLayout.rowInset)
        .onHover { hovering = $0 }
        .opacity(dimmed ? 0.35 : 1)
        .contentShape(.rect)
        .onTapGesture(count: 2, perform: onDoubleClick)
        .onTapGesture(perform: onSelect)
        // Tap gestures are invisible to VoiceOver: expose the row as one
        // selectable element with a readable summary, and name the
        // double-click action so it's reachable from the actions rotor.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { onSelect() }
        .accessibilityAction(named: "Check out", onDoubleClick)
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
        let row = HStack(spacing: Spacing.s6) {
            Avatar(name: commit.authorName, size: 16, colorSeed: commit.authorEmail)
            Text(commit.authorName)
                .textRole(.callout)
                .foregroundStyle(theme.colors.textSecondary)
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

    /// "Fix login crash, Ana, 2h ago, commit 1a2b3c4, main, v1.2".
    private var accessibilitySummary: String {
        var parts = [commit.subject, commit.authorName,
                     preferences.dateDisplayMode.format(commit.authorDate),
                     "commit \(commit.shortSha)"]
        parts += refs.map(\.displayName)
        return parts.joined(separator: ", ")
    }

    private func copy(_ string: String) {
        NSPasteboard.general.declareTypes([.string], owner: nil)
        NSPasteboard.general.setString(string, forType: .string)
    }

    /// Re-uses the existing `GraphColumnView` so lane drawing matches the
    /// rest of the app.
    private var graphGutter: some View {
        GraphColumnView(
            row: layout,
            maxLanes: max(maxLanes, 1),
            style: graphStyle,
            isHeadCommit: isHeadCommit,
            isSelected: isSelected,
            isHovered: hovering
        )
    }

    private var gap: some View {
        Color.clear.frame(width: HistoryTableLayout.gap)
    }

    /// Redesign spec §5 list row: accent-soft selected, hover fill otherwise.
    private var rowBackground: Color {
        if rowDropTargeted { return theme.colors.accentSoft }
        if isSelected { return theme.colors.accentSoft }
        return hovering ? theme.colors.fillHover : .clear
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    let commit = Commit.previewSamples[0]
    VStack(spacing: 0) {
        CommitRow(
            commit: commit,
            layout: [GraphRowLayout].previewSamples[1],
            maxLanes: 2,
            rowHeight: 28,
            tableLayout: HistoryTableLayout(viewport: 1100, graph: 80, author: 112, date: 92, commit: 64),
            refs: GitRef.previewSamples,
            currentBranch: "main",
            isSelected: true,
            dimmed: false,
            onSelect: {}, onDoubleClick: {}, onBranchDrop: nil
        )
        CommitRow(
            commit: Commit.previewSamples[1],
            layout: [GraphRowLayout].previewSamples[2],
            maxLanes: 2,
            rowHeight: 28,
            tableLayout: HistoryTableLayout(viewport: 1100, graph: 80, author: 112, date: 92, commit: 64),
            refs: [],
            currentBranch: "main",
            isSelected: false,
            dimmed: false,
            onSelect: {}, onDoubleClick: {}, onBranchDrop: nil
        )
        CommitRow(
            commit: Commit.previewSamples[2],
            layout: [GraphRowLayout].previewSamples[3],
            maxLanes: 2,
            rowHeight: 28,
            tableLayout: HistoryTableLayout(viewport: 1100, graph: 80, author: 112, date: 92, commit: 64),
            refs: [],
            currentBranch: "main",
            isSelected: false,
            dimmed: true,
            onSelect: {}, onDoubleClick: {}, onBranchDrop: nil
        )
    }
    .frame(width: 1100)
    .background(theme.colors.bgContent)
    .appTheme(theme)
}
