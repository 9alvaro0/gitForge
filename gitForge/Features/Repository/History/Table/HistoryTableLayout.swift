import CoreGraphics

/// Column geometry of the History table (redesign spec §6.2): Graph ·
/// Description · Author · Date · Commit. Description takes the rest of the
/// row; the others keep the user's widths, and the user can hide any of them
/// from the header's menu. When the pane is too narrow, Author goes first;
/// only below that does Description hold its floor and the table scroll
/// horizontally.
nonisolated struct HistoryTableLayout: Equatable, Sendable {
    /// The columns besides Description, which always shows. Raw values are
    /// the `ResizableTableModel` column ids.
    nonisolated enum Column: String, CaseIterable, Sendable {
        case graph
        case author
        case date = "when"
        case commit = "sha"
    }

    /// Rows sit inset from the pane edge so the rounded selection floats.
    static let rowInset: CGFloat = 6
    static let leadingPadding: CGFloat = 8
    static let trailingPadding: CGFloat = 12
    /// Space between adjacent columns (where the resize handles live).
    static let gap: CGFloat = 8
    /// Space between adjacent rows. The graph's lines cross it: the halves
    /// drawn by adjacent rows join in its middle (`GraphRowGeometry`).
    static let rowSpacing: CGFloat = 1
    static let minDescription: CGFloat = 200
    /// Extra room Description needs before an Author that didn't fit comes
    /// back. Without it, a divider dragged around the threshold makes the
    /// column flicker in and out.
    static let authorReturnMargin: CGFloat = 32

    /// Widths are 0 for hidden columns.
    let graph: CGFloat
    let description: CGFloat
    let author: CGFloat
    let date: CGFloat
    let commit: CGFloat
    let showsGraph: Bool
    let showsAuthor: Bool
    let showsDate: Bool
    let showsCommit: Bool
    /// Whether Author fits next to Description. Pass it back as
    /// `authorFitted` on the next pass. While the user hides Author it stays
    /// as passed in.
    let authorFits: Bool

    /// `authorFitted` is the previous pass's `authorFits`: an Author that
    /// didn't fit needs `authorReturnMargin` more room to come back.
    init(viewport: CGFloat, graph: CGFloat, author: CGFloat, date: CGFloat, commit: CGFloat,
         hidden: Set<Column> = [], authorFitted: Bool = true) {
        showsGraph = !hidden.contains(.graph)
        showsDate = !hidden.contains(.date)
        showsCommit = !hidden.contains(.commit)
        self.graph = showsGraph ? graph : 0
        self.date = showsDate ? date : 0
        self.commit = showsCommit ? commit : 0

        let withoutAuthor = Self.chrome + Self.slot(self.graph, showsGraph)
            + Self.slot(self.date, showsDate) + Self.slot(self.commit, showsCommit)
        if hidden.contains(.author) {
            authorFits = authorFitted
        } else {
            let floor = Self.minDescription + (authorFitted ? 0 : Self.authorReturnMargin)
            authorFits = viewport - withoutAuthor - Self.slot(author, true) >= floor
        }
        showsAuthor = !hidden.contains(.author) && authorFits
        self.author = showsAuthor ? author : 0
        let fixed = withoutAuthor + Self.slot(self.author, showsAuthor)
        description = max(Self.minDescription, viewport - fixed)
    }

    /// Everything except Description.
    var fixedWidth: CGFloat {
        Self.chrome + Self.slot(graph, showsGraph) + Self.slot(author, showsAuthor)
            + Self.slot(date, showsDate) + Self.slot(commit, showsCommit)
    }

    /// Full row width; wider than the viewport once Description hits its floor.
    var totalWidth: CGFloat { fixedWidth + description }

    /// What Description can give up before it hits its floor. Widening any
    /// column past this would hide Author mid-drag, so handles stop there.
    var descriptionSlack: CGFloat { max(0, description - Self.minDescription) }

    /// Insets and paddings around the columns.
    private static var chrome: CGFloat { 2 * rowInset + leadingPadding + trailingPadding }

    /// A shown column takes its width plus the gap that separates it from
    /// Description's side.
    private static func slot(_ width: CGFloat, _ shown: Bool) -> CGFloat {
        shown ? width + gap : 0
    }
}
