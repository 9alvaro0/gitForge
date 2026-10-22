import SwiftUI
import Testing
@testable import gitForge

/// What `CommitRow` does for a ghost, a commit that only exists on the server (graph v3 spec §4.3).
@Suite("History — ghost rows")
@MainActor
struct CommitRowGhostTests {

    private static func layout(isGhost: Bool) -> GraphRow {
        GraphRow(node: GraphNode(column: 0, kind: .commit, color: .head, isGhost: isGhost),
                 stepsAbove: [], stepsBelow: [], width: 1)
    }

    private static func commitRow(_ layout: GraphRow) -> CommitRow {
        CommitRow(commit: Commit.previewSamples[0], layout: layout, maxLanes: 1, rowHeight: 28,
                  tableLayout: HistoryTableLayout(viewport: 1100, graph: 80, author: 112, date: 92, commit: 64),
                  refs: [], currentBranch: nil, isSelected: false, dimmed: false,
                  onSelect: {}, onDoubleClick: {}, onBranchDrop: nil)
    }

    @Test("A ghost's subject is as quiet as its date and sha; any other commit's is primary")
    func subjectColor() {
        let colors = GFColors.make(.dark, accent: .violet)
        #expect(CommitRow.subjectColor(isGhost: true, colors: colors) == colors.textTertiary)
        #expect(CommitRow.subjectColor(isGhost: false, colors: colors) == colors.textPrimary)
    }

    @Test("Rows that differ only in being a ghost are not equal, so the table redraws one that becomes real")
    func equalityCoversGhost() {
        #expect(Self.commitRow(Self.layout(isGhost: true)) != Self.commitRow(Self.layout(isGhost: false)))
        #expect(Self.commitRow(Self.layout(isGhost: true)) == Self.commitRow(Self.layout(isGhost: true)))
    }

    @Test("Rows whose style differs only in the ghost opacity are not equal, so Increase Contrast redraws them")
    func equalityCoversGhostOpacity() {
        var translucent = Self.commitRow(Self.layout(isGhost: true))
        var opaque = translucent
        translucent.graphStyle = GraphStyle(ghostOpacity: 0.6)
        opaque.graphStyle = GraphStyle(ghostOpacity: 1)
        #expect(translucent != opaque)
    }
}
