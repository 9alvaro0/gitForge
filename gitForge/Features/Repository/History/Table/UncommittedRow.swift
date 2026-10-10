import SwiftUI

/// "Uncommitted changes" row pinned to the top of the log when the working
/// tree is dirty. Mirrors the column layout of a real `CommitRow` so the
/// graph gutter and column boundaries line up, and behaves like a row — a
/// single tap selects it (host wires the click into the working-copy file
/// list + diff pane), and a double tap can be routed elsewhere if needed.
struct UncommittedRow: View {
    let rowHeight: CGFloat
    let layout: HistoryTableLayout
    let isSelected: Bool
    let onSelect: () -> Void
    var onDoubleClick: (() -> Void)? = nil

    @Environment(\.appTheme) private var theme

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2)
                .strokeBorder(theme.colors.mod, style: StrokeStyle(lineWidth: 1.5, dash: [2.5, 2]))
                .frame(width: 9, height: 9)
                .padding(.leading, theme.density.metrics.graph.firstLaneX - 4.5)
                .frame(width: layout.graph, alignment: .leading)
            Color.clear.frame(width: HistoryTableLayout.gap)
            Text("Uncommitted changes")
                .textRole(.body)
                .italic()
                .foregroundStyle(theme.colors.mod)
                .frame(width: layout.description, alignment: .leading)
            Color.clear.frame(width: HistoryTableLayout.gap + layout.author + HistoryTableLayout.gap)
            Text("now")
                .textRole(.callout)
                .foregroundStyle(theme.colors.textTertiary)
                .frame(width: layout.date, alignment: .leading)
            Color.clear.frame(width: HistoryTableLayout.gap)
            Text("–")
                .textRole(.monoSmall)
                .foregroundStyle(theme.colors.textTertiary)
                .frame(width: layout.commit, alignment: .trailing)
            Spacer(minLength: 0)
        }
        .padding(.leading, HistoryTableLayout.leadingPadding)
        .padding(.trailing, HistoryTableLayout.trailingPadding)
        .frame(height: rowHeight)
        .background(RoundedRectangle(cornerRadius: Radius.row).fill(rowBackground))
        .padding(.horizontal, HistoryTableLayout.rowInset)
        .onHover { hovering = $0 }
        .contentShape(.rect)
        .onTapGesture(count: 2) { onDoubleClick?() }
        .onTapGesture(perform: onSelect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Uncommitted changes")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { onSelect() }
    }

    private var rowBackground: Color {
        if isSelected { return theme.colors.accentSoft }
        return hovering ? theme.colors.fillHover : theme.colors.modSoft.opacity(0.5)
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    @Previewable @State var columns = ResizableTableModel.historyColumns(id: "history.uncommitted.preview")
    VStack(spacing: 0) {
        UncommittedRow(rowHeight: 28, layout: HistoryTableLayout(viewport: 1100, graph: 80, author: 112, date: 92, commit: 64), isSelected: false, onSelect: {})
        UncommittedRow(rowHeight: 28, layout: HistoryTableLayout(viewport: 1100, graph: 80, author: 112, date: 92, commit: 64), isSelected: true, onSelect: {})
    }
    .frame(width: 1100)
    .background(theme.palette.bg2)
    .appTheme(theme)
}
