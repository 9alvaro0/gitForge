import Foundation
import Testing
@testable import gitForge

@Suite("GraphColumns")
struct GraphColumnsTests {

    /// Stages 1 to 3 of the layout, chained.
    private struct Result {
        let lines: GraphLines
        let connections: GraphConnections
        let columns: GraphColumns

        func column(of owner: GraphOwner) -> Int? {
            lines.lines.firstIndex { $0.owner == owner }.map { columns.columnOfLine[$0] }
        }
    }

    private func columns(_ input: GraphInput) -> Result {
        let rowOf = input.rowIndex()
        var lines = GraphLines.build(input, rowOf: rowOf)
        let connections = GraphConnections.build(input, rowOf: rowOf, lines: &lines)
        let columns = GraphColumns.assign(input, lines: lines, connections: connections)
        return Result(lines: lines, connections: connections, columns: columns)
    }

    /// Every line and track as `(column, first row, last row)`, with the same
    /// intervals the assignment reasons about.
    private func intervals(_ r: Result) -> [(column: Int, start: Int, end: Int)] {
        let lines = r.lines.lines.enumerated().map { index, line in
            (column: r.columns.columnOfLine[index], start: line.top, end: line.bottom)
        }
        let tracks = r.connections.tracks.enumerated().map { index, track in
            (column: r.columns.columnOfTrack[index], start: track.mergeRow, end: track.parentRow ?? Int.max)
        }
        return lines + tracks
    }

    /// Whether two of the intervals that share a column overlap, ends included.
    private func hasOverlap(_ r: Result) -> Bool {
        let all = intervals(r)
        for (i, a) in all.enumerated() {
            for b in all[(i + 1)...] where a.column == b.column && a.start <= b.end && b.start <= a.end {
                return true
            }
        }
        return false
    }

    @Test("Gitflow on a feature matches the reference layout")
    func gitflow() {
        let r = columns(GraphInput(commits: GraphFixture.gitflow, headSha: "cartPayment",
                                   refs: GraphFixture.gitflowRefs(head: "feature/cart")))
        #expect(r.column(of: .branch("feature/cart")) == 0)
        #expect(r.column(of: .branch("main")) == 1)
        #expect(r.column(of: .branch("develop")) == 2)
        #expect(r.column(of: .branch("feature/search")) == 3)
        #expect(r.column(of: .branch("release/1.1")) == 4)
        #expect(r.column(of: .branch("feature/login")) == 4)
        #expect(r.column(of: .branch("hotfix/crash")) == 5)
        #expect(r.columns.columnOfTrack == [3])
        #expect(r.columns.count == 6)
    }

    @Test("A line ending on a row and one starting on it never share a column")
    func strictIntervals() {
        let r = columns(GraphInput(commits: GraphFixture.gitflow, headSha: "cartPayment",
                                   refs: GraphFixture.gitflowRefs(head: "feature/cart")))
        #expect(r.column(of: .branch("feature/search")) != r.column(of: .branch("release/1.1")))
    }

    @Test("HEAD's tip past the first page is not reserved", arguments: [[Int](), [2, 4]])
    func headOutsideFirstPage(pageEnds: [Int]) {
        let r = columns(GraphInput(commits: GraphFixture.commits("x y\ny r\nh r\nr"), pageEnds: pageEnds, headSha: "h",
                                   refs: [GraphFixture.local("other", "x"), GraphFixture.local("feature", "h", head: true)]))
        #expect(r.column(of: .branch("feature")) == (pageEnds.isEmpty ? 0 : 1))
    }

    @Test("A trunk whose tip is past the first page is not reserved")
    func trunkOutsideFirstPage() {
        let r = columns(GraphInput(commits: GraphFixture.commits("f r\nx y\ny r\nm r\nr"), pageEnds: [3, 5], headSha: "f",
                                   refs: [GraphFixture.local("feature", "f", head: true), GraphFixture.local("other", "x"),
                                          GraphFixture.local("main", "m")]))
        #expect(r.column(of: .branch("other")) == 1)
        #expect(r.column(of: .branch("main")) == 2)
    }

    @Test("A sticky track takes the nearest free column right of its merge")
    func stickyTrackGoesRight() {
        let r = columns(GraphInput(commits: GraphFixture.commits("m a x\na"), headSha: "m",
                                   refs: [GraphFixture.local("main", "m", head: true)]))
        #expect(r.columns.columnOfTrack == [1])
    }

    // MARK: - Beyond the plan's cases

    @Test("A detached HEAD takes column 0 and trunks sit right of it")
    func detachedHead() {
        // HEAD sits on `h`, below main's tip `n`, which is born from it.
        let r = columns(GraphInput(commits: GraphFixture.commits("n h\nh r\nr"), headSha: "h",
                                   refs: [GraphFixture.local("main", "n")]))
        #expect(r.column(of: .head) == 0)
        #expect(r.column(of: .branch("main")) == 1)
    }

    @Test("Rank 0 is reserved before rank 1, whatever their rows")
    func reservedRankOrder() {
        // develop's tip is above main's, and both are in the first page.
        let r = columns(GraphInput(commits: GraphFixture.commits("d b\nm b\nb r\nf r\nr"), headSha: "f",
                                   refs: [GraphFixture.local("feature", "f", head: true),
                                          GraphFixture.local("develop", "d"), GraphFixture.local("main", "m")]))
        #expect(r.column(of: .branch("feature")) == 0)
        #expect(r.column(of: .branch("main")) == 1)
        #expect(r.column(of: .branch("develop")) == 2)
    }

    @Test("A track whose target line starts below its merge takes the nearest free column right of the merge")
    func trackBeforeItsTarget() {
        // m (row 0) merges b (row 2); side's commit s (row 1) lies between them, so it is a track.
        // side starts at row 1, after the track has been placed.
        let r = columns(GraphInput(commits: GraphFixture.commits("m r b\ns b\nb r\nr"), headSha: "m",
                                   refs: [GraphFixture.local("main", "m", head: true), GraphFixture.local("side", "s")]))
        #expect(r.connections.tracks.map(\.sticky) == [false])
        #expect(r.columns.columnOfTrack == [1])
        #expect(r.column(of: .branch("side")) == 2)
    }

    @Test("A track takes the free column nearest its parent's line, inside the span of its merge and parent")
    func trackNearestToParent() {
        // Columns: work 0, x 1, xa 2, y 3. The track from m (row 6) to y2 (row 8) can use column 1 or 2,
        // both free by then; it takes 2, nearest to y.
        let commits = GraphFixture.commits("""
            x0 x1
            xa xb
            y0 y1
            x1
            xb
            h m
            m r y2
            y1 y2
            y2 r
            r
            """)
        let r = columns(GraphInput(commits: commits, headSha: "h",
                                   refs: [GraphFixture.local("work", "h", head: true), GraphFixture.local("x", "x0"),
                                          GraphFixture.local("xa", "xa"), GraphFixture.local("y", "y0")]))
        #expect(r.column(of: .branch("work")) == 0)
        #expect(r.column(of: .branch("x")) == 1)
        #expect(r.column(of: .branch("xa")) == 2)
        #expect(r.column(of: .branch("y")) == 3)
        #expect(r.connections.tracks.map(\.sticky) == [false])
        #expect(r.columns.columnOfTrack == [2])
    }

    @Test("A track merging an ancestor of its own line leans on that line's column")
    func trackToOwnLine() {
        let r = columns(GraphInput(commits: GraphFixture.commits("m b a\nb a\na"), headSha: "m",
                                   refs: [GraphFixture.local("main", "m", head: true)]))
        #expect(r.columns.columnOfTrack == [1])
        #expect(r.columns.count == 2)
    }

    @Test("An open track and the line right of it do not collide")
    func stickyTrackBlocksItsColumn() {
        // main's merge has an unloaded parent, so its track runs to the bottom edge in column 1.
        let r = columns(GraphInput(commits: GraphFixture.commits("m a x\nf r\na r\nr"), headSha: "m",
                                   refs: [GraphFixture.local("main", "m", head: true), GraphFixture.local("feature", "f")]))
        #expect(r.columns.columnOfTrack == [1])
        #expect(r.column(of: .branch("feature")) == 2)
    }

    @Test("A log with no commits still counts one column")
    func empty() {
        let r = columns(GraphInput(commits: []))
        #expect(r.columns.columnOfLine.isEmpty)
        #expect(r.columns.columnOfTrack.isEmpty)
        #expect(r.columns.count == 1)
    }

    @Test("No two lines or tracks overlap in a column, across heads and page splits",
          arguments: [nil, "feature/cart", "develop", "main", "hotfix/crash"] as [String?],
          [[Int](), [12, 24], [6, 12, 18, 24], [1, 24]])
    func noOverlap(head: String?, pageEnds: [Int]) {
        let sha = head.flatMap { name in GraphFixture.gitflowRefs(head: head).first { $0.name == name }?.targetSha }
        let r = columns(GraphInput(commits: GraphFixture.gitflow, pageEnds: pageEnds, headSha: sha,
                                   refs: GraphFixture.gitflowRefs(head: head)))
        #expect(!hasOverlap(r))
        #expect(r.columns.columnOfLine.allSatisfy { $0 >= 0 && $0 < r.columns.count })
        #expect(r.columns.columnOfTrack.allSatisfy { $0 >= 0 && $0 < r.columns.count })
    }
}
