import SwiftUI

/// Column titles of the History table, with the resize handles and the menu
/// that shows or hides columns.
///
/// Each handle sits on the edge that moves when its column resizes, so the
/// divider follows the pointer: Graph's on its trailing edge (it's anchored
/// left), and the columns after Description on their leading edge (they
/// hang off the table's trailing edge, `inverted`). Description is flexible,
/// so it has none of its own.
struct CommitTableHeader: View {
    let layout: HistoryTableLayout
    let graphHandle: Binding<CGFloat>
    let graphMinWidth: CGFloat
    /// Double-click on the Graph handle: back to fitting the lanes.
    let onFitGraph: () -> Void
    let columns: ResizableTableModel

    @Environment(\.appTheme) private var theme

    /// Widest each column may grow by dragging, whatever Description leaves.
    private static let maxGraph: CGFloat = 600
    private static let maxAuthor: CGFloat = 280
    private static let maxDate: CGFloat = 200
    private static let maxCommit: CGFloat = 160

    var body: some View {
        HStack(spacing: 0) {
            if layout.showsGraph {
                Text("Graph").frame(width: layout.graph, alignment: .leading)
                ColumnDragHandle(width: graphHandle,
                                 minWidth: graphMinWidth,
                                 maxWidth: Self.handleMax(width: layout.graph, min: graphMinWidth,
                                                          slack: layout.descriptionSlack, cap: Self.maxGraph),
                                 onCommit: { columns.commit() },
                                 onDoubleClick: onFitGraph,
                                 doubleClickActionName: String(localized: "Fit to graph"))
            }
            Text("Description").frame(width: layout.description, alignment: .leading)
            if layout.showsAuthor {
                leadingHandle(.author, width: layout.author, cap: Self.maxAuthor)
                Text("Author").frame(width: layout.author, alignment: .leading)
            }
            if layout.showsDate {
                leadingHandle(.date, width: layout.date, cap: Self.maxDate)
                Text("Date").frame(width: layout.date, alignment: .leading)
            }
            if layout.showsCommit {
                leadingHandle(.commit, width: layout.commit, cap: Self.maxCommit)
                Text(String(localized: "history.column.commit", defaultValue: "Commit"))
                    .frame(width: layout.commit, alignment: .trailing)
            }
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
            ForEach(HistoryTableLayout.Column.allCases, id: \.self) { column in
                Toggle(Self.title(of: column), isOn: Binding(
                    get: { columns.isVisible(column.rawValue) },
                    set: { columns.setVisible(column.rawValue, $0) }
                ))
            }
            Divider()
            Button("Reset column widths") { columns.reset() }
        }
    }

    /// Handle for a column after Description, on its leading edge.
    private func leadingHandle(_ column: HistoryTableLayout.Column, width: CGFloat, cap: CGFloat) -> some View {
        let id = column.rawValue
        let min = columns.minWidth(id)
        return ColumnDragHandle(width: columns.binding(for: id),
                                minWidth: min,
                                maxWidth: Self.handleMax(width: width, min: min,
                                                         slack: layout.descriptionSlack, cap: cap),
                                inverted: true,
                                onCommit: { columns.commit() },
                                onDoubleClick: { columns.resetWidth(id) })
    }

    /// A column grows only by what Description can give before its floor,
    /// so a drag never pushes Author out, and never past `cap`.
    nonisolated static func handleMax(width: CGFloat, min: CGFloat, slack: CGFloat, cap: CGFloat) -> CGFloat {
        Swift.min(cap, Swift.max(min, width + slack))
    }

    static func title(of column: HistoryTableLayout.Column) -> String {
        switch column {
        case .graph: String(localized: "Graph")
        case .author: String(localized: "Author")
        case .date: String(localized: "Date")
        case .commit: String(localized: "history.column.commit", defaultValue: "Commit")
        }
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    @Previewable @State var columns = ResizableTableModel.historyColumns(id: "history.header.preview")
    CommitTableHeader(
        layout: HistoryTableLayout(viewport: 900, graph: 80, author: 112, date: 92, commit: 64),
        graphHandle: columns.binding(for: "graph"),
        graphMinWidth: 60,
        onFitGraph: {},
        columns: columns
    )
    .frame(width: 1100)
    .background(theme.colors.bgContent)
    .appTheme(theme)
}
