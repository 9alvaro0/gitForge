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

    @Test("appendPage never removes rows from the pages already loaded")
    func appendKeepsEarlierPages() {
        let vm = Self.makeVM()
        // The first page is read before the stash is known, so its index
        // commit stays; dropping it later would shift every drawn row.
        vm.history.replaceLog(with: GraphFixture.commits("s a idx\nidx\na"))
        vm.stashes = [Stash(index: 0, sha: "s", subject: "WIP")]
        vm.history.appendPage(GraphFixture.commits("z"))
        #expect(vm.history.commits.map(\.sha) == ["s", "idx", "a", "z"])
        #expect(vm.history.graphPageEnds == [3, 4])
        #expect(vm.history.loadedRawCount == 4)
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

    @Test("purge forgets the pages")
    func purge() {
        let vm = Self.makeVM()
        vm.history.replaceLog(with: GraphFixture.commits("c b\nb"))
        vm.history.purge()
        #expect(vm.history.graphPageEnds.isEmpty)
        #expect(vm.history.graphLayouts.isEmpty)
    }
}
