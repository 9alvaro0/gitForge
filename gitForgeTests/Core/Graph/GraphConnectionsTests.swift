import Foundation
import Testing
@testable import gitForge

@Suite("GraphConnections")
struct GraphConnectionsTests {

    private func connect(_ input: GraphInput) -> (GraphLines, GraphConnections) {
        let rowOf = input.rowIndex()
        var lines = GraphLines.build(input, rowOf: rowOf)
        let connections = GraphConnections.build(input, rowOf: rowOf, lines: &lines)
        return (lines, connections)
    }

    private func lineIndex(_ owner: GraphOwner, _ lines: GraphLines) -> Int {
        guard let index = lines.lines.firstIndex(where: { $0.owner == owner }) else {
            preconditionFailure("No line owned by \(owner)")
        }
        return index
    }

    @Test("Gitflow on a feature: five joins, one track, raised tops")
    func gitflow() {
        let (lines, c) = connect(GraphInput(commits: GraphFixture.gitflow, headSha: "cartPayment",
                                            refs: GraphFixture.gitflowRefs(head: "feature/cart")))
        #expect(Set(c.joins.map(\.mergeRow)) == [4, 10, 13, 14, 20])
        #expect(c.tracks == [GraphTrack(mergeRow: 7, parentRow: 14, fromLine: 0,
                                        toLine: lineIndex(.branch("develop"), lines), sticky: false)])
        #expect(lines.lines[lineIndex(.branch("release/1.1"), lines)].top == 4)
        #expect(lines.lines[lineIndex(.branch("hotfix/crash"), lines)].top == 13)
        #expect(lines.lines[lineIndex(.branch("feature/login"), lines)].top == 14)
    }

    @Test("A join records the merge's line, the parent's row and the parent's line")
    func joinEndpoints() {
        let (lines, c) = connect(GraphInput(commits: GraphFixture.gitflow, headSha: "cartPayment",
                                            refs: GraphFixture.gitflowRefs(head: "feature/cart")))
        let release = lineIndex(.branch("release/1.1"), lines)
        #expect(c.joins.contains(GraphJoin(mergeRow: 4, parentRow: 11, fromLine: lineIndex(.branch("develop"), lines),
                                           toLine: release)))
        #expect(c.joins.contains(GraphJoin(mergeRow: 10, parentRow: 11, fromLine: lineIndex(.branch("main"), lines),
                                           toLine: release)))
    }

    @Test("A parent past the merge's page makes a sticky track")
    func stickyAcrossPages() {
        let (_, c) = connect(GraphInput(commits: GraphFixture.gitflow, pageEnds: [12, 24], headSha: "cartPayment",
                                        refs: GraphFixture.gitflowRefs(head: "feature/cart")))
        #expect(c.tracks.first { $0.mergeRow == 7 }?.sticky == true)
    }

    @Test("A sticky track still names the parent's row and line")
    func stickyKeepsEndpoints() {
        let (lines, c) = connect(GraphInput(commits: GraphFixture.gitflow, pageEnds: [12, 24], headSha: "cartPayment",
                                            refs: GraphFixture.gitflowRefs(head: "feature/cart")))
        #expect(c.tracks.first { $0.mergeRow == 7 } == GraphTrack(
            mergeRow: 7, parentRow: 14, fromLine: 0, toLine: lineIndex(.branch("develop"), lines), sticky: true))
    }

    @Test("A parent on the next page is a track even where it would join, and raises nothing")
    func stickyBeatsJoin() {
        // The release tip (row 11) is the parent of the merges at rows 4 and 10. With the first
        // page ending at 11 it falls on the second one, so neither merge joins it.
        let (lines, c) = connect(GraphInput(commits: GraphFixture.gitflow, pageEnds: [11, 24], headSha: "cartPayment",
                                            refs: GraphFixture.gitflowRefs(head: "feature/cart")))
        let release = lineIndex(.branch("release/1.1"), lines)
        #expect(c.joins.allSatisfy { $0.toLine != release })
        #expect(c.tracks.filter { $0.toLine == release }.map(\.sticky) == [true, true])
        #expect(lines.lines[release].top == 11)
    }

    @Test("An unloaded parent makes a sticky open track")
    func unloadedParent() {
        let (_, c) = connect(GraphInput(commits: GraphFixture.commits("m a x\na"), headSha: "m",
                                        refs: [GraphFixture.local("main", "m", head: true)]))
        #expect(c.tracks == [GraphTrack(mergeRow: 0, parentRow: nil, fromLine: 0, toLine: nil, sticky: true)])
    }

    @Test("Merging an ancestor of the same line is a track; a repeated parent is ignored")
    func degenerate() {
        let ancestor = connect(GraphInput(commits: GraphFixture.commits("m b a\nb a\na"), headSha: "m",
                                          refs: [GraphFixture.local("main", "m", head: true)])).1
        #expect(ancestor.joins.isEmpty)
        #expect(ancestor.tracks == [GraphTrack(mergeRow: 0, parentRow: 2, fromLine: 0, toLine: 0, sticky: false)])
        let repeated = connect(GraphInput(commits: GraphFixture.commits("m a a\na"), headSha: "m",
                                          refs: [GraphFixture.local("main", "m", head: true)])).1
        #expect(repeated.joins.isEmpty && repeated.tracks.isEmpty)
    }

    @Test("An extra parent repeated among the extras is connected once")
    func repeatedExtraParent() {
        let c = connect(GraphInput(commits: GraphFixture.commits("m a b b\na r\nb r\nr"), headSha: "m",
                                   refs: [GraphFixture.local("main", "m", head: true)])).1
        #expect(c.joins.count + c.tracks.count == 1)
    }

    @Test("An octopus merge connects every extra parent")
    func octopus() {
        let (_, c) = connect(GraphInput(commits: GraphFixture.commits("m a b c\na r\nb r\nc r\nr"), headSha: "m",
                                        refs: [GraphFixture.local("main", "m", head: true)]))
        #expect(c.joins.count + c.tracks.count == 2)
    }

    @Test("A stash's index and untracked parents are not connections")
    func stashParents() {
        let (_, c) = connect(GraphInput(commits: GraphFixture.commits("s base idx\nbase"), stashShas: ["s"]))
        #expect(c.joins.isEmpty && c.tracks.isEmpty)
    }

    @Test("A commit of the parent's line between the merge and the parent makes a track")
    func commitInBetween() {
        // side owns rows 1 (s1) and 3 (s0); m at row 0 merges s0, so s1 sits strictly between them.
        let commits = GraphFixture.commits("m x s0\ns1 s0\nx base\ns0 base\nbase")
        let (lines, c) = connect(GraphInput(commits: commits, headSha: "m",
                                            refs: [GraphFixture.local("main", "m", head: true),
                                                   GraphFixture.local("side", "s1")]))
        let side = lineIndex(.branch("side"), lines)
        #expect(c.joins.isEmpty)
        #expect(c.tracks == [GraphTrack(mergeRow: 0, parentRow: 3, fromLine: 0, toLine: side, sticky: false)])
        #expect(lines.lines[side].top == 1)
    }

    @Test("Joining below a line's tip leaves its top alone")
    func joinIntoTheMiddle() {
        // side owns rows 0 (s1) and 3 (s0). m at row 1 merges s0 and nothing of side lies between
        // rows 1 and 3, so it joins, but s0 is not the tip: the line already starts higher.
        let commits = GraphFixture.commits("s1 s0\nm x s0\nx base\ns0 base\nbase")
        let (lines, c) = connect(GraphInput(commits: commits, headSha: "m",
                                            refs: [GraphFixture.local("main", "m", head: true),
                                                   GraphFixture.local("side", "s1")]))
        let side = lineIndex(.branch("side"), lines)
        #expect(c.joins == [GraphJoin(mergeRow: 1, parentRow: 3, fromLine: lineIndex(.branch("main"), lines),
                                      toLine: side)])
        #expect(c.tracks.isEmpty)
        #expect(lines.lines[side].top == 0)
    }
}
