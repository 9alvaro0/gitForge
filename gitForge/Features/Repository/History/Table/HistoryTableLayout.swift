import CoreGraphics

/// Column geometry of the History table (redesign spec §6.2): Graph ·
/// Description · Author · Date · Commit. Graph, Author, Date and Commit keep
/// the user's resizable widths; Description takes the rest. When the pane is
/// too narrow, Author goes first; only below that does Description hold its
/// floor and the table scroll horizontally.
nonisolated struct HistoryTableLayout: Equatable, Sendable {
    /// Rows sit inset from the pane edge so the rounded selection floats.
    static let rowInset: CGFloat = 6
    static let leadingPadding: CGFloat = 8
    static let trailingPadding: CGFloat = 12
    /// Space between adjacent columns (where the resize handles live).
    static let gap: CGFloat = 8
    static let minDescription: CGFloat = 200

    let graph: CGFloat
    let description: CGFloat
    /// 0 when hidden.
    let author: CGFloat
    let date: CGFloat
    let commit: CGFloat
    let showsAuthor: Bool

    init(viewport: CGFloat, graph: CGFloat, author: CGFloat, date: CGFloat, commit: CGFloat) {
        self.graph = graph
        self.date = date
        self.commit = commit
        let withAuthor = Self.fixedWidth(graph: graph, author: author, date: date, commit: commit, showsAuthor: true)
        if viewport - withAuthor >= Self.minDescription {
            self.showsAuthor = true
            self.author = author
            self.description = viewport - withAuthor
        } else {
            self.showsAuthor = false
            self.author = 0
            let withoutAuthor = Self.fixedWidth(graph: graph, author: 0, date: date, commit: commit, showsAuthor: false)
            self.description = max(Self.minDescription, viewport - withoutAuthor)
        }
    }

    /// Everything except Description.
    var fixedWidth: CGFloat {
        Self.fixedWidth(graph: graph, author: author, date: date, commit: commit, showsAuthor: showsAuthor)
    }

    /// Full row width; wider than the viewport once Description hits its floor.
    var totalWidth: CGFloat { fixedWidth + description }

    private static func fixedWidth(graph: CGFloat, author: CGFloat, date: CGFloat, commit: CGFloat,
                                   showsAuthor: Bool) -> CGFloat {
        let gaps: CGFloat = showsAuthor ? 4 : 3
        return 2 * rowInset + leadingPadding + trailingPadding + gaps * gap + graph + author + date + commit
    }
}
