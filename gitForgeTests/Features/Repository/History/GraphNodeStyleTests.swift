import Foundation
import Testing
@testable import gitForge

@Suite("Graph — node style")
struct GraphNodeStyleTests {

    private static func row(_ kind: GraphNode.Kind) -> GraphRow {
        GraphRow(node: GraphNode(column: 0, kind: kind, color: .neutral, isGhost: false),
                 stepsAbove: [], stepsBelow: [], width: 1)
    }

    @Test("Stash wins, then HEAD, then merge, else a plain commit")
    func precedence() {
        #expect(GraphNodeStyle.for(Self.row(.commit), isHeadCommit: false) == .commit)
        #expect(GraphNodeStyle.for(Self.row(.merge), isHeadCommit: false) == .merge)
        #expect(GraphNodeStyle.for(Self.row(.commit), isHeadCommit: true) == .head)
        #expect(GraphNodeStyle.for(Self.row(.merge), isHeadCommit: true) == .head)
        #expect(GraphNodeStyle.for(Self.row(.stash), isHeadCommit: true) == .stash)
        #expect(GraphNodeStyle.for(Self.row(.stash), isHeadCommit: false) == .stash)
    }
}
