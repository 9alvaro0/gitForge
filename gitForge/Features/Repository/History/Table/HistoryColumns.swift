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
                (id: "graph",     defaultWidth: 110, minWidth: 80),
                (id: "branchTag", defaultWidth: 220, minWidth: 80),
                (id: "message",   defaultWidth: 480, minWidth: 240),
                (id: "author",    defaultWidth: 130, minWidth: 80),
                (id: "sha",       defaultWidth: 80,  minWidth: 60),
                (id: "when",      defaultWidth: 70,  minWidth: 50),
            ]
        )
    }
}
