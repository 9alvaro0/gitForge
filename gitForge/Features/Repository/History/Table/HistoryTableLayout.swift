import CoreGraphics

/// Column geometry of the History table (redesign spec §6.2): Graph ·
/// Description · Author · Date · Commit. Graph, Author, Date and Commit keep
/// the user's resizable widths; Description takes the rest, down to a floor,
/// below which the table scrolls horizontally.
nonisolated struct HistoryTableLayout: Equatable, Sendable {
    /// Rows sit inset from the pane edge so the rounded selection floats.
    static let rowInset: CGFloat = 6
    static let leadingPadding: CGFloat = 8
    static let trailingPadding: CGFloat = 12
    /// Space between adjacent columns (where the resize handles live).
    static let gap: CGFloat = 8
    static let minDescription: CGFloat = 240

    let graph: CGFloat
    let description: CGFloat
    let author: CGFloat
    let date: CGFloat
    let commit: CGFloat

    init(viewport: CGFloat, graph: CGFloat, author: CGFloat, date: CGFloat, commit: CGFloat) {
        self.graph = graph
        self.author = author
        self.date = date
        self.commit = commit
        let fixed = Self.fixedWidth(graph: graph, author: author, date: date, commit: commit)
        self.description = max(Self.minDescription, viewport - fixed)
    }

    /// Everything except Description.
    var fixedWidth: CGFloat {
        Self.fixedWidth(graph: graph, author: author, date: date, commit: commit)
    }

    /// Full row width; wider than the viewport once Description hits its floor.
    var totalWidth: CGFloat { fixedWidth + description }

    private static func fixedWidth(graph: CGFloat, author: CGFloat, date: CGFloat, commit: CGFloat) -> CGFloat {
        2 * rowInset + leadingPadding + trailingPadding + 4 * gap + graph + author + date + commit
    }
}
