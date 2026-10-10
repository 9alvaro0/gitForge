import Foundation

extension ResizableTableModel {
    /// Column layout of the History table — the single source of truth for
    /// the table itself and every preview that renders a row or header.
    /// `id` namespaces the persisted widths; previews pass their own so
    /// resizing one never moves the real table's columns.
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
            ]
        )
    }
}
