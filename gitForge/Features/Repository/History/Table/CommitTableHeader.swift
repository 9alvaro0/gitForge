import SwiftUI

struct CommitTableHeader: View {
    let layout: HistoryTableLayout
    let graphHandle: Binding<CGFloat>
    let graphMinWidth: CGFloat
    let columns: ResizableTableModel

    @Environment(\.appTheme) private var theme

    /// Handles sit in the gap after the column they resize (Excel-style).
    /// Description is flexible, so it has none.
    var body: some View {
        HStack(spacing: 0) {
            Text("Graph").frame(width: layout.graph, alignment: .leading)
            ColumnDragHandle(width: graphHandle,
                             minWidth: graphMinWidth, maxWidth: 600,
                             onCommit: { columns.commit() })
            Text("Description").frame(width: layout.description, alignment: .leading)
            Color.clear.frame(width: HistoryTableLayout.gap)
            Text("Author").frame(width: layout.author, alignment: .leading)
            ColumnDragHandle(width: columns.binding(for: "author"),
                             minWidth: columns.minWidth("author"), maxWidth: 280,
                             onCommit: { columns.commit() })
            Text("Date").frame(width: layout.date, alignment: .leading)
            ColumnDragHandle(width: columns.binding(for: "when"),
                             minWidth: columns.minWidth("when"), maxWidth: 200,
                             onCommit: { columns.commit() })
            Text("Commit").frame(width: layout.commit, alignment: .trailing)
            ColumnDragHandle(width: columns.binding(for: "sha"),
                             minWidth: columns.minWidth("sha"), maxWidth: 160,
                             onCommit: { columns.commit() })
            Spacer(minLength: 0)
        }
        .textRole(.caption, weight: .semibold)
        .foregroundStyle(theme.colors.textQuaternary)
        .lineLimit(1)
        .padding(.leading, HistoryTableLayout.rowInset + HistoryTableLayout.leadingPadding)
        .frame(height: theme.density.metrics.rowHeader)
        .background(theme.colors.bgContent)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.colors.separator).frame(height: 1) }
        .contextMenu {
            Button("Reset column widths") { columns.reset() }
        }
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    @Previewable @State var columns = ResizableTableModel.historyColumns(id: "history.header.preview")
    CommitTableHeader(
        layout: HistoryTableLayout(viewport: 900, graph: 80, author: 112, date: 92, commit: 64),
        graphHandle: columns.binding(for: "graph"),
        graphMinWidth: 80,
        columns: columns
    )
    .frame(width: 1100)
    .background(theme.colors.bgContent)
    .appTheme(theme)
}
