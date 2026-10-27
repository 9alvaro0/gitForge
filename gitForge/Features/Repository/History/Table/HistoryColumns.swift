import Foundation

extension ResizableTableModel {
    /// Column layout of the History table — the single source of truth for
    /// the table itself and every preview that renders a row or header.
    /// `id` namespaces the persisted widths; previews pass their own so
    /// resizing one never moves the real table's columns. Ids match
    /// `HistoryTableLayout.Column`.
    static func historyColumns(id: String = "history") -> ResizableTableModel {
        ResizableTableModel(
            id: id,
            columns: [
                // Description has no entry: it takes the rest of the row
                // (`HistoryTableLayout`).
                (id: "graph",  defaultWidth: 80,  minWidth: 60),
                (id: "author", defaultWidth: 112, minWidth: 80),
                (id: "when",   defaultWidth: 92,  minWidth: 50),
                (id: "sha",    defaultWidth: 64,  minWidth: 56),
            ],
            // The graph fits its lanes until the user drags it
            // (`CommitGraphTable.autoGraphWidth`).
            autoSized: ["graph"]
        )
    }

    /// The History columns the user hid from the header's menu.
    var hiddenHistoryColumns: Set<HistoryTableLayout.Column> {
        Set(hidden.compactMap(HistoryTableLayout.Column.init(rawValue:)))
    }
}
