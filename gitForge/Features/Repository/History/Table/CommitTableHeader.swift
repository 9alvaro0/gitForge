import SwiftUI

struct CommitTableHeader: View {
    let gutterWidth: CGFloat
    let graphHandle: Binding<CGFloat>
    let graphMinWidth: CGFloat
    let columns: ResizableTableModel

    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.none) {
            Text("GRAPH").frame(width: gutterWidth, alignment: .leading)
            ColumnDragHandle(width: graphHandle,
                             minWidth: graphMinWidth, maxWidth: 600,
                             onCommit: { columns.commit() })
            Text("BRANCH / TAG")
                .frame(width: columns.width("branchTag"), alignment: .leading)
            ColumnDragHandle(width: columns.binding(for: "branchTag"),
                             minWidth: columns.minWidth("branchTag"), maxWidth: 480,
                             onCommit: { columns.commit() })
            Text("MESSAGE")
                .frame(width: columns.width("message"), alignment: .leading)
            ColumnDragHandle(width: columns.binding(for: "message"),
                             minWidth: columns.minWidth("message"), maxWidth: 1200,
                             onCommit: { columns.commit() })
            Text("AUTHOR")
                .frame(width: columns.width("author"), alignment: .leading)
            ColumnDragHandle(width: columns.binding(for: "author"),
                             minWidth: columns.minWidth("author"), maxWidth: 280,
                             onCommit: { columns.commit() })
            Text("SHA")
                .frame(width: columns.width("sha"), alignment: .leading)
            ColumnDragHandle(width: columns.binding(for: "sha"),
                             minWidth: columns.minWidth("sha"), maxWidth: 200,
                             onCommit: { columns.commit() })
            Text("WHEN")
                .frame(width: columns.width("when"), alignment: .trailing)
            ColumnDragHandle(width: columns.binding(for: "when"),
                             minWidth: columns.minWidth("when"), maxWidth: 160,
                             onCommit: { columns.commit() })
            Spacer(minLength: 0)
        }
        .font(AppFont.mono(10.5, family: theme.monoFont))
        .tracking(0.6)
        .foregroundStyle(theme.palette.fg3)
        .padding(.horizontal, DesignTokens.Spacing.xxxxl)
        .frame(height: DesignTokens.Control.height)
        .background(theme.palette.bg1)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.palette.line).frame(height: DesignTokens.Stroke.regular) }
        .contextMenu {
            Button("Reset column widths") { columns.reset() }
        }
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    @Previewable @State var columns = ResizableTableModel(
        id: "history.header.preview",
        columns: [
            (id: "graph",     defaultWidth: 110, minWidth: 80),
            (id: "branchTag", defaultWidth: 220, minWidth: 80),
            (id: "message",   defaultWidth: 480, minWidth: 240),
            (id: "author",    defaultWidth: 130, minWidth: 80),
            (id: "sha",       defaultWidth: 80,  minWidth: 60),
            (id: "when",      defaultWidth: 70,  minWidth: 50),
        ]
    )
    CommitTableHeader(
        gutterWidth: 110,
        graphHandle: columns.binding(for: "graph"),
        graphMinWidth: 80,
        columns: columns
    )
    .frame(width: 1100)
    .background(theme.palette.bg2)
    .appTheme(theme)
}
