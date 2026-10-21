import Foundation
import Testing
@testable import gitForge

@Suite("Graph — node style")
struct GraphNodeStyleTests {

    private static func row(_ kind: GraphNode.Kind, isGhost: Bool = false) -> GraphRow {
        GraphRow(node: GraphNode(column: 0, kind: kind, color: .neutral, isGhost: isGhost),
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

    @Test("A ghost row draws the ghost node, merge or not; stash and HEAD still win")
    func ghostPrecedence() {
        #expect(GraphNodeStyle.for(Self.row(.commit, isGhost: true), isHeadCommit: false) == .ghost)
        #expect(GraphNodeStyle.for(Self.row(.merge, isGhost: true), isHeadCommit: false) == .ghost)
        #expect(GraphNodeStyle.for(Self.row(.stash, isGhost: false), isHeadCommit: true) == .stash)
        #expect(GraphNodeStyle.for(Self.row(.stash, isGhost: true), isHeadCommit: false) == .stash)
        #expect(GraphNodeStyle.for(Self.row(.commit, isGhost: true), isHeadCommit: true) == .head)
    }
}
