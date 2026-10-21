import Foundation
import Testing
@testable import gitForge

@Suite("HistoryStore — graph input and pages", .serialized)
@MainActor
struct HistoryStoreGraphTests {

    private static func makeVM() -> RepositoryViewModel {
        let url = URL(fileURLWithPath: "/var/empty/gitForge-tests-\(UUID().uuidString)")
        return RepositoryViewModel(repository: Repository(url: url))
    }

    @Test("replaceLog starts the page list; appendPage extends it after dropping stash internals")
    func pageEnds() {
        let vm = Self.makeVM()
        vm.history.replaceLog(with: GraphFixture.commits("c b\nb a"))
        #expect(vm.history.graphPageEnds == [2])
        vm.stashes = [Stash(index: 0, sha: "s", subject: "WIP")]
        vm.history.appendPage(GraphFixture.commits("s a idx\nidx\na"))
        #expect(vm.history.commits.map(\.sha) == ["c", "b", "s", "a"])
        #expect(vm.history.graphPageEnds == [2, 4])
    }

    @Test("appendPage never removes or changes rows from the pages already loaded")
    func appendKeepsEarlierPages() {
        let vm = Self.makeVM()
        // The first page is read before the stash is known, so its index
        // commit stays; dropping it later would shift every drawn row.
        vm.history.replaceLog(with: GraphFixture.commits("s a idx\nidx\na"))
        let firstRow = vm.history.graphLayouts[0]
        vm.stashes = [Stash(index: 0, sha: "s", subject: "WIP")]
        vm.history.appendPage(GraphFixture.commits("z"))
        #expect(vm.history.commits.map(\.sha) == ["s", "idx", "a", "z"])
        #expect(vm.history.graphPageEnds == [3, 4])
        #expect(vm.history.loadedRawCount == 4)
        // `s` is not a row of the new page, so it doesn't become a stash.
        #expect(vm.history.loadedStashShas.isEmpty)
        #expect(vm.history.graphLayouts[0] == firstRow)
        Self.expectPublished(vm.history)
    }

    @Test("A stash that is a row of the appended page joins the log's stashes")
    func appendedStash() {
        let vm = Self.makeVM()
        vm.history.replaceLog(with: GraphFixture.commits("c b\nb a"))
        vm.stashes = [Stash(index: 0, sha: "s", subject: "WIP")]
        vm.history.appendPage(GraphFixture.commits("s a idx\nidx\na"))
        #expect(vm.history.loadedStashShas == ["s"])
        #expect(vm.history.graphLayouts[2].node.kind == .stash)
        Self.expectPublished(vm.history)
    }

    @Test("An appended page skips commits already loaded but still counts them for --skip")
    func appendSkipsLoadedCommits() {
        let vm = Self.makeVM()
        vm.history.replaceLog(with: GraphFixture.commits("c b\nb a"))
        // The log grew between the two pages, so `b` comes back.
        vm.history.appendPage(GraphFixture.commits("b a\na"))
        #expect(vm.history.commits.map(\.sha) == ["c", "b", "a"])
        #expect(vm.history.loadedRawCount == 4)
        #expect(vm.history.graphPageEnds == [2, 3])
        Self.expectPublished(vm.history)
    }

    @Test("A page that adds no rows adds no page end")
    func emptyPage() {
        let vm = Self.makeVM()
        vm.history.replaceLog(with: GraphFixture.commits("c b\nb"))
        vm.history.appendPage([])
        #expect(vm.history.graphPageEnds == [2])
    }

    @Test("graphInput carries HEAD, refs, stashes, pages and the palette size")
    func input() async {
        let vm = Self.makeVM()
        vm.refs = [GraphFixture.local("main", "c", head: true)]
        vm.headSha = "c"
        vm.stashes = [Stash(index: 0, sha: "s", subject: "WIP")]
        vm.history.replaceLog(with: GraphFixture.commits("c b\nb"))
        await vm.history.setGraphPaletteSize(3)
        let input = vm.history.graphInput()
        #expect(input.headSha == "c" && input.headBranch == "main")
        #expect(input.stashShas == ["s"] && input.pageEnds == [2] && input.paletteSize == 3)
    }

    @Test("The palette size starts at the violet pool and recomputes only when it changes")
    func paletteSize() async {
        let vm = Self.makeVM()
        #expect(vm.history.graphPaletteSize == LaneColors.pool(accent: .violet).count)
        let before = vm.history.graphLayoutGen
        await vm.history.setGraphPaletteSize(vm.history.graphPaletteSize)
        #expect(vm.history.graphLayoutGen == before)
        await vm.history.setGraphPaletteSize(3)
        #expect(vm.history.graphLayoutGen == before &+ 1)
    }

    @Test("recomputeGraph publishes the engine's rows and column count")
    func recompute() async {
        let vm = Self.makeVM()
        vm.refs = GraphFixture.gitflowRefs(head: "feature/cart")
        vm.headSha = "cartPayment"
        vm.history.replaceLog(with: GraphFixture.gitflow)
        await vm.history.recomputeGraph()
        let expected = CommitGraphEngine.layout(vm.history.graphInput())
        #expect(vm.history.graphLayouts == expected.rows)
        #expect(vm.history.graphMaxLanes == expected.columnCount)
        #expect(vm.history.graphMaxLanes == 6)
    }

    /// The published graph describes the published log: one row each, and the
    /// engine's layout of the store's own input.
    private static func expectPublished(_ history: HistoryStore, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(history.graphLayouts.count == history.commits.count, sourceLocation: sourceLocation)
        let expected = CommitGraphEngine.layout(history.graphInput())
        #expect(history.graphLayouts == expected.rows, sourceLocation: sourceLocation)
        #expect(history.graphMaxLanes == expected.columnCount, sourceLocation: sourceLocation)
    }

    @Test("Replacing or appending a page publishes the rows with their graph")
    func publishedTogether() {
        let vm = Self.makeVM()
        vm.refs = GraphFixture.gitflowRefs(head: "feature/cart")
        vm.headSha = "cartPayment"
        vm.history.replaceLog(with: Array(GraphFixture.gitflow.prefix(12)))
        Self.expectPublished(vm.history)
        vm.history.appendPage(Array(GraphFixture.gitflow.dropFirst(12)))
        Self.expectPublished(vm.history)
        #expect(vm.history.graphPageEnds == [12, 24])
    }

    @Test("A refs-only recompute keeps drawing the loaded log's stash after the live list drops it")
    func refsRecomputeKeepsLoadedStashes() async {
        let vm = Self.makeVM()
        vm.stashes = [Stash(index: 0, sha: "s", subject: "WIP")]
        vm.history.replaceLog(with: GraphFixture.commits("s a idx\nidx\na"))
        #expect(vm.history.commits.map(\.sha) == ["s", "a"])
        // `git stash drop`: loadRefs lands the new list before the log reloads.
        vm.stashes = []
        await vm.history.recomputeGraph()
        #expect(vm.history.graphInput().stashShas == ["s"])
        #expect(vm.history.graphLayouts.first?.node.kind == .stash)
        Self.expectPublished(vm.history)
    }

    // MARK: Interleavings

    /// Lays graphs out like the real engine, but holds the passes listed in
    /// `holding` (by call order, from 0) until the test opens their gate.
    nonisolated final class HeldEngine: @unchecked Sendable {
        private let lock = NSLock()
        private let gates: [Int: AsyncGate]
        private var count = 0

        init(holding: [Int]) {
            gates = Dictionary(uniqueKeysWithValues: holding.map { ($0, AsyncGate()) })
        }

        var calls: Int { lock.withLock { count } }

        func gate(_ pass: Int) -> AsyncGate { gates[pass]! }

        func layout(_ input: GraphInput) async -> GraphLayout {
            let pass = lock.withLock {
                defer { count += 1 }
                return count
            }
            if let gate = gates[pass] { await gate.wait() }
            return CommitGraphEngine.layout(input)
        }
    }

    private static func hold(_ vm: RepositoryViewModel, passes: [Int]) -> HeldEngine {
        let engine = HeldEngine(holding: passes)
        vm.history.graphEngine = { await engine.layout($0) }
        return engine
    }

    @Test("A recompute that finishes after a newer log was published is dropped")
    func staleRecomputeDropped() async {
        let vm = Self.makeVM()
        vm.history.replaceLog(with: GraphFixture.commits("c b\nb a\na"))
        let engine = Self.hold(vm, passes: [0])
        async let recompute: Void = vm.history.recomputeGraph()
        await engine.gate(0).waiting()
        #expect(await vm.history.publish(vm.history.stageNextPage(GraphFixture.commits("z"))))
        Self.expectPublished(vm.history)
        engine.gate(0).open()
        await recompute
        #expect(vm.history.commits.map(\.sha) == ["c", "b", "a", "z"])
        Self.expectPublished(vm.history)
        // The page was staged after the recompute was asked for: no extra pass.
        #expect(engine.calls == 2)
    }

    @Test("A page held while a recompute lands is still published, then laid out with the new refs")
    func pageSurvivesRecompute() async {
        let vm = Self.makeVM()
        vm.refs = [GraphFixture.local("main", "c", head: true), GraphFixture.local("topic", "b")]
        vm.headSha = "c"
        vm.history.replaceLog(with: GraphFixture.commits("c b\nb a"))
        let engine = Self.hold(vm, passes: [0])
        async let published = vm.history.publish(vm.history.stageNextPage(GraphFixture.commits("a")))
        await engine.gate(0).waiting()
        // A checkout lands while the page is laid out.
        vm.refs = [GraphFixture.local("main", "c"), GraphFixture.local("topic", "b", head: true)]
        vm.headSha = "b"
        await vm.history.recomputeGraph()
        #expect(vm.history.commits.map(\.sha) == ["c", "b"])
        Self.expectPublished(vm.history)
        engine.gate(0).open()
        #expect(await published)
        #expect(vm.history.commits.map(\.sha) == ["c", "b", "a"])
        // Staged with the old HEAD, so it laid itself out again before install: page, recompute, page again.
        Self.expectPublished(vm.history)
        #expect(engine.calls == 3)
    }

    @Test("A refs change landing during a reload's layout pass is installed only with the new refs")
    func refsChangeDuringReload() async {
        let vm = Self.makeVM()
        vm.refs = [GraphFixture.local("main", "c", head: true), GraphFixture.local("topic", "b")]
        vm.headSha = "c"
        vm.history.replaceLog(with: GraphFixture.commits("c b\nb a\na"))
        let engine = Self.hold(vm, passes: [0, 2])
        async let published = vm.history.publish(vm.history.stageFirstPage(GraphFixture.commits("d c\nc b\nb a\na")))
        await engine.gate(0).waiting()
        // `refresh()`: loadRefs lands a checkout while the reload is laid out.
        vm.refs = [GraphFixture.local("main", "c"), GraphFixture.local("topic", "b", head: true)]
        vm.headSha = "b"
        await vm.history.recomputeGraph()
        engine.gate(0).open()
        await engine.gate(2).waiting()
        // The pass with the old HEAD is done, but nothing laid out with it was shown.
        #expect(vm.history.commits.map(\.sha) == ["c", "b", "a"])
        Self.expectPublished(vm.history)
        engine.gate(2).open()
        #expect(await published)
        #expect(vm.history.commits.map(\.sha) == ["d", "c", "b", "a"])
        Self.expectPublished(vm.history)
        #expect(engine.calls == 3)
    }

    @Test("An older publish never writes its follow-up state over a newer reload")
    func olderPublishCannotOverwrite() async {
        let vm = Self.makeVM()
        vm.history.replaceLog(with: GraphFixture.commits("c b\nb"))
        let engine = Self.hold(vm, passes: [0, 2])
        vm.history.hasMore = true
        // A short final page that would end pagination…
        async let older = vm.history.publish(vm.history.stageNextPage(GraphFixture.commits("z"))) {
            vm.history.hasMore = false
        }
        await engine.gate(0).waiting()
        // …is laid out while a checkout's refs land, so it needs another pass.
        await vm.history.recomputeGraph()
        engine.gate(0).open()
        await engine.gate(2).waiting()
        // A newer reload publishes a full first page meanwhile.
        vm.history.logGen &+= 1
        #expect(await vm.history.publish(vm.history.stageFirstPage(GraphFixture.commits("d c\nc b\nb"))) {
            vm.history.hasMore = true
        })
        engine.gate(2).open()
        #expect(await older == false)
        #expect(vm.history.hasMore)
        #expect(vm.history.commits.map(\.sha) == ["d", "c", "b"])
        Self.expectPublished(vm.history)
    }

    @Test("loadInitial never resets a selection made after a newer reload published")
    func loadInitialKeepsLaterSelection() async throws {
        let repo = try await GitTestRepo.make { repo in
            for index in 0..<3 { try repo.commit("c\(index)", files: ["f.txt": "\(index)\n"]) }
        }
        defer { repo.remove() }
        let vm = RepositoryViewModel(repository: Repository(url: repo.url))
        let engine = Self.hold(vm, passes: [0, 1])
        async let initial: Void = vm.history.loadInitial()
        await engine.gate(0).waiting()
        // Refs land while the first page is laid out, so its pass runs again.
        await vm.history.recomputeGraph()
        engine.gate(0).open()
        await engine.gate(1).waiting()
        // A reload publishes meanwhile and the user picks a commit.
        await vm.history.reloadLog()
        let picked = try #require(vm.history.commits.last?.sha)
        vm.history.selectedCommitId = picked
        engine.gate(1).open()
        await initial
        #expect(vm.history.selectedCommitId == picked)
        Self.expectPublished(vm.history)
    }

    @Test("A reload superseded by a newer one never publishes over it")
    func supersededReload() async {
        let vm = Self.makeVM()
        let engine = Self.hold(vm, passes: [0])
        async let older = vm.history.publish(vm.history.stageFirstPage(GraphFixture.commits("old")))
        await engine.gate(0).waiting()
        vm.history.logGen &+= 1 // a newer reload starts
        #expect(await vm.history.publish(vm.history.stageFirstPage(GraphFixture.commits("new"))))
        engine.gate(0).open()
        #expect(await older == false)
        #expect(vm.history.commits.map(\.sha) == ["new"])
        Self.expectPublished(vm.history)
    }

    @Test("A page staged on a log that a reload has since replaced is dropped")
    func pageOnReplacedLog() async {
        let vm = Self.makeVM()
        vm.history.replaceLog(with: GraphFixture.commits("c b\nb"))
        let staged = vm.history.stageNextPage(GraphFixture.commits("z"))
        vm.history.replaceLog(with: GraphFixture.commits("d c\nc b\nb"))
        #expect(await vm.history.publish(staged) == false)
        #expect(vm.history.commits.map(\.sha) == ["d", "c", "b"])
        #expect(vm.history.graphPageEnds == [3])
        Self.expectPublished(vm.history)
    }

    @Test("purge forgets the pages")
    func purge() {
        let vm = Self.makeVM()
        vm.history.replaceLog(with: GraphFixture.commits("c b\nb"))
        vm.history.purge()
        #expect(vm.history.graphPageEnds.isEmpty)
        #expect(vm.history.graphLayouts.isEmpty)
    }
}
