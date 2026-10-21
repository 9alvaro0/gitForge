import Foundation
import Testing
@testable import gitForge

@Suite("GraphLines")
struct GraphLinesTests {

    private func lines(_ input: GraphInput) -> GraphLines {
        GraphLines.build(input, rowOf: input.rowIndex())
    }

    private func line(_ owner: GraphOwner, in result: GraphLines) -> GraphLine? {
        result.lines.first { $0.owner == owner }
    }

    @Test("A linear history is one line owned by its branch")
    func linear() {
        let input = GraphInput(commits: GraphFixture.commits("d c\nc b\nb a\na"),
                               headSha: "d", refs: [GraphFixture.local("main", "d", head: true)])
        let result = lines(input)
        #expect(result.lines.count == 1)
        #expect(result.lines[0] == GraphLine(owner: .branch("main"), rows: [0, 1, 2, 3], top: 0,
                                             forkRow: nil, continuesPastEnd: false))
    }

    @Test("Gitflow on a feature: HEAD's line runs to the root, colours follow the gitflow owners")
    func gitflowOnFeature() {
        let input = GraphInput(commits: GraphFixture.gitflow, headSha: "cartPayment",
                               refs: GraphFixture.gitflowRefs(head: "feature/cart"))
        let result = lines(input)
        #expect(result.lines[0].owner == .branch("feature/cart"))
        #expect(result.lines[0].rows == [5, 6, 7, 8, 9, 19, 22, 23])
        #expect(line(.branch("main"), in: result)?.rows == [10, 20])
        #expect(line(.branch("main"), in: result)?.forkRow == 22)
        #expect(line(.branch("develop"), in: result)?.rows == [3, 4, 13, 14, 18])
        #expect(line(.branch("develop"), in: result)?.forkRow == 19)
        #expect(line(.branch("release/1.1"), in: result)?.rows == [11, 12])
        #expect(line(.branch("feature/search"), in: result)?.forkRow == 4)
        #expect(line(.branch("feature/login"), in: result)?.rows == [15, 16, 17])
        #expect(line(.branch("hotfix/crash"), in: result)?.rows == [21])
        #expect(result.colorOwnerOfRow[7] == .branch("feature/cart"))
        #expect(result.colorOwnerOfRow[19] == .branch("develop"))
        #expect(result.colorOwnerOfRow[22] == .branch("main"))
        #expect(result.colorOwnerOfRow[23] == .branch("main"))
    }

    @Test("Gitflow on develop: develop's line runs to the root")
    func gitflowOnDevelop() {
        let input = GraphInput(commits: GraphFixture.gitflow, headSha: "devDeps",
                               refs: GraphFixture.gitflowRefs(head: "develop"))
        let result = lines(input)
        #expect(result.lines[0].rows == [3, 4, 13, 14, 18, 19, 22, 23])
        #expect(result.colorOwnerOfRow[19] == .branch("develop"))
        #expect(result.colorOwnerOfRow[22] == .branch("main"))
    }

    @Test("Stacked branches: the base keeps its commits whichever one is HEAD", arguments: ["feature/a", "feature/a-2"])
    func stacked(head: String) {
        let commits = GraphFixture.commits("a2 a1\na1 b\nb base\nbase")
        let refs = [GraphFixture.local("main", "base"),
                    GraphFixture.local("feature/a", "b", head: head == "feature/a"),
                    GraphFixture.local("feature/a-2", "a2", head: head == "feature/a-2")]
        let result = lines(GraphInput(commits: commits, headSha: head == "feature/a" ? "b" : "a2", refs: refs))
        #expect(result.colorOwnerOfRow == [.branch("feature/a-2"), .branch("feature/a-2"),
                                           .branch("feature/a"), .branch("main")])
    }

    @Test("Detached HEAD mid-history: its line starts at that commit; colours keep the branch owners")
    func detachedMidHistory() {
        let input = GraphInput(commits: GraphFixture.gitflow, headSha: "devBase",
                               refs: GraphFixture.gitflowRefs(head: nil))
        let result = lines(input)
        #expect(result.lines[0].owner == .head)
        #expect(result.lines[0].rows == [19, 22, 23])
        #expect(result.colorOwnerOfRow[19] == .branch("develop"))
    }

    @Test("A stash owns only its commit; an orphaned parent gets an unnamed line")
    func stash() {
        let input = GraphInput(commits: GraphFixture.commits("s p\np r\nr"), stashShas: ["s"])
        let result = lines(input)
        #expect(line(.stash("s"), in: result) == GraphLine(owner: .stash("s"), rows: [0], top: 0,
                                                           forkRow: 1, continuesPastEnd: false))
        #expect(line(.unnamed(1), in: result)?.rows == [1, 2])
    }

    @Test("A stash whose parent is not loaded keeps its line open")
    func stashWithUnloadedParent() {
        let input = GraphInput(commits: GraphFixture.commits("s p"), stashShas: ["s"])
        let result = lines(input)
        #expect(line(.stash("s"), in: result) == GraphLine(owner: .stash("s"), rows: [0], top: 0,
                                                           forkRow: nil, continuesPastEnd: true))
    }

    @Test("Orphan roots end at their own root")
    func orphans() {
        let input = GraphInput(commits: GraphFixture.commits("a r1\nb r2\nr1\nr2"), headSha: "a",
                               refs: [GraphFixture.local("main", "a", head: true), GraphFixture.local("gh-pages", "b")])
        let result = lines(input)
        #expect(line(.branch("main"), in: result)?.rows == [0, 2])
        #expect(line(.branch("gh-pages"), in: result)?.rows == [1, 3])
        #expect(result.lines.allSatisfy { $0.forkRow == nil && !$0.continuesPastEnd })
    }

    @Test("A first parent beyond the loaded rows keeps the line open; unloaded ref tips are ignored")
    func pastEnd() {
        let input = GraphInput(commits: GraphFixture.commits("c b"), headSha: "c",
                               refs: [GraphFixture.local("main", "c", head: true), GraphFixture.local("old", "zzz")])
        let result = lines(input)
        #expect(result.lines.count == 1)
        #expect(result.lines[0].continuesPastEnd)
    }

    @Test("Only behind its upstream: the local line starts at the upstream tip")
    func behindContinues() {
        let input = GraphInput(commits: GraphFixture.commits("u2 u1\nu1 l\nl base\nbase"), headSha: "l",
                               refs: [GraphFixture.local("main", "l", head: true, upstream: "origin/main", ahead: 0, behind: 2),
                                      GraphFixture.remote("origin/main", "u2")])
        let result = lines(input)
        #expect(result.lines[0].owner == .branch("main"))
        #expect(result.lines[0].rows == [0, 1, 2, 3])
        #expect(!result.lines.contains { $0.owner == .remote("origin/main") })
    }

    @Test("Diverged from its upstream: the remote gets its own line born at the merge base")
    func diverged() {
        let input = GraphInput(commits: GraphFixture.commits("r1 b\nl b\nb base\nbase"), headSha: "l",
                               refs: [GraphFixture.local("feature", "l", head: true, upstream: "origin/feature", ahead: 1, behind: 1),
                                      GraphFixture.remote("origin/feature", "r1")])
        let result = lines(input)
        #expect(line(.remote("origin/feature"), in: result)?.rows == [0])
        #expect(line(.remote("origin/feature"), in: result)?.forkRow == 2)
        #expect(result.lines[0].rows == [1, 2, 3])
    }

    @Test("The lines partition the rows and every row points back at its line")
    func partition() {
        let input = GraphInput(commits: GraphFixture.gitflow, headSha: "cartPayment",
                               refs: GraphFixture.gitflowRefs(head: "feature/cart"))
        let result = lines(input)
        #expect(result.lineOfRow.count == input.commits.count)
        #expect(result.colorOwnerOfRow.count == input.commits.count)
        #expect(result.lines.flatMap(\.rows).sorted() == Array(0..<input.commits.count))
        for (index, line) in result.lines.enumerated() {
            #expect(line.rows.allSatisfy { result.lineOfRow[$0] == index })
            #expect(line.top == line.rows[0])
        }
    }

    @Test("Commits no ref reaches open unnamed lines, top to bottom")
    func unnamed() {
        let input = GraphInput(commits: GraphFixture.commits("a r\nx y\ny r\nr"), headSha: "a",
                               refs: [GraphFixture.local("main", "a", head: true)])
        let result = lines(input)
        #expect(line(.unnamed(1), in: result)?.rows == [1, 2])
        #expect(line(.unnamed(1), in: result)?.forkRow == 3)
        #expect(result.colorOwnerOfRow == [.branch("main"), .unnamed(1), .unnamed(1), .branch("main")])
    }

    @Test("Branch priority ranks the trunk first and gitflow prefixes by prefix")
    func priority() {
        #expect(["main", "master", "trunk"].allSatisfy { GraphPriority.rank($0) == 0 })
        #expect(["develop", "dev"].allSatisfy { GraphPriority.rank($0) == 1 })
        #expect(GraphPriority.rank("release/1.1") == 2)
        #expect(GraphPriority.rank("hotfix/crash") == 3)
        #expect(["feature/x", "release", "hotfix", "mainline", "origin/main"].allSatisfy { GraphPriority.rank($0) == 4 })
    }

    @Test("The page end of a row is the first page end past it, or the end of the log")
    func pageEndSearch() {
        let log = (0..<12).map { "c\($0) c\($0 + 1)" }.joined(separator: "\n")
        let input = GraphInput(commits: GraphFixture.commits(log), pageEnds: [2, 5, 9])
        let expected = [2, 2, 5, 5, 5, 9, 9, 9, 9, 12, 12, 12]
        #expect((0..<12).map { input.pageEnd(containing: $0) } == expected)
        #expect(GraphInput(commits: GraphFixture.commits(log), pageEnds: [12]).pageEnd(containing: 11) == 12)
    }

    @Test("Input helpers: head branch, page boundaries and first-occurrence row index")
    func inputHelpers() {
        let commits = GraphFixture.commits("a b\nb c\nc\nb")
        let refs = [GraphFixture.local("main", "a", head: true), GraphFixture.local("other", "c")]
        let paged = GraphInput(commits: commits, pageEnds: [2, 3], refs: refs)
        #expect(paged.headBranch == "main")
        #expect(paged.firstPageEnd == 2)
        #expect(paged.pageEnd(containing: 1) == 2)
        #expect(paged.pageEnd(containing: 2) == 3)
        #expect(paged.pageEnd(containing: 3) == 4)
        #expect(paged.rowIndex() == ["a": 0, "b": 1, "c": 2])

        let single = GraphInput(commits: commits, refs: [GraphFixture.local("main", "a")])
        #expect(single.headBranch == nil)
        #expect(single.firstPageEnd == 4)
        #expect(single.pageEnd(containing: 0) == 4)
    }
}
