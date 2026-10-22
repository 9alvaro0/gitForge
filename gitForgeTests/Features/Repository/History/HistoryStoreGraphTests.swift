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

    @Test("graphInput carries the remote trunks read from the refs and the remote HEADs")
    func remoteTrunksInInput() {
        let vm = Self.makeVM()
        vm.refs = [GraphFixture.local("feature", "f", head: true), GraphFixture.remote("origin/main", "m")]
        vm.remoteHeads = ["origin": "origin/main"]
        vm.history.replaceLog(with: GraphFixture.commits("f m\nm"))
        #expect(vm.history.graphInput().remoteTrunks == ["origin/main": 0])
    }

    @Test("The published log keeps the scope it was fetched with; it goes stale when a remote in it moves")
    func staleScope() async {
        let vm = Self.makeVM()
        vm.refs = [GraphFixture.local("main", "m", head: true, upstream: "origin/main", ahead: 0, behind: 1),
                   GraphFixture.remote("origin/main", "u2")]
        await vm.history.publish(vm.history.stageFirstPage(GraphFixture.commits("u2 m\nm")))
        #expect(vm.history.loadedScope?.remoteTips == ["origin/main": "u2"] && !vm.history.isScopeStale)
        vm.refs = [GraphFixture.local("main", "m", head: true, upstream: "origin/main", ahead: 0, behind: 2),
                   GraphFixture.remote("origin/main", "u3")]
        #expect(vm.history.isScopeStale)
    }

    @Test("Until the log reloads, a remote branch of its scope that moved stays where the log was loaded with it")
    func movedRemoteStaysUntilReload() async {
        let vm = Self.makeVM()
        vm.refs = [GraphFixture.local("main", "m", head: true, upstream: "origin/main", ahead: 0, behind: 2),
                   GraphFixture.remote("origin/main", "u2")]
        vm.headSha = "m"
        await vm.history.publish(vm.history.stageFirstPage(GraphFixture.commits("u2 u1\nu1 m\nm a")))
        let pull = GraphNode(column: 0, kind: .commit, color: .head, isGhost: true)
        #expect(vm.history.graphLayouts.prefix(2).map(\.node) == [pull, pull])

        // A fetch moves origin/main to a commit the log doesn't have; its refs land before the reload.
        vm.refs = [GraphFixture.local("main", "m", head: true, upstream: "origin/main", ahead: 0, behind: 3),
                   GraphFixture.remote("origin/main", "u3")]
        #expect(vm.history.isScopeStale)
        await vm.history.recomputeGraph()
        #expect(vm.history.graphLayouts.prefix(2).map(\.node) == [pull, pull])
        #expect(vm.history.refChips.refs(on: "u2").map(\.name) == ["origin/main"])
        Self.expectPublished(vm.history)

        // So does a page appended before the reload.
        vm.history.appendPage(GraphFixture.commits("a"))
        #expect(vm.history.graphLayouts.prefix(2).map(\.node) == [pull, pull])
        #expect(vm.history.refChips.refs(on: "u2").map(\.name) == ["origin/main"])
        Self.expectPublished(vm.history)
    }

    @Test("graphScope is the current scope's revisions, remote tips by sha")
    func graphScopeWithRemotes() {
        let vm = Self.makeVM()
        vm.refs = [GraphFixture.local("main", "m", head: true, upstream: "origin/main", ahead: 0, behind: 1),
                   GraphFixture.remote("origin/main", "u2")]
        vm.unmergedLocalBranchRefs = ["refs/heads/topic"]
        #expect(vm.history.graphScope() == ["HEAD", "refs/heads/topic", "u2", "--tags"])
        #expect(vm.history.graphScope() == vm.history.currentScope().revisions)
    }

    // MARK: Remote branches toggle

    /// A store for the repository at `url` that remembers its toggle in `defaults` and reads
    /// its refs from `source`. The repository needn't exist: a reload then fails and sets
    /// `loadError`, which these tests don't look at.
    private static func makeStore(_ url: URL, defaults: TestDefaults, source: RepositoryViewModel) -> HistoryStore {
        let store = HistoryStore(cli: GitCLI(workingDirectory: url), tasks: OwnedTasks(),
                                 repositoryURL: url, defaults: defaults.defaults)
        store.refsSource = source
        return store
    }

    private static func missingRepositoryURL() -> URL {
        URL(fileURLWithPath: "/var/empty/gitForge-tests-\(UUID().uuidString)")
    }

    @Test("The remote branches toggle is remembered per repository")
    func toggleRemembered() async {
        let suite = TestDefaults()
        defer { suite.remove() }
        let vm = Self.makeVM()
        let urlA = Self.missingRepositoryURL()
        let urlB = Self.missingRepositoryURL()
        let store = Self.makeStore(urlA, defaults: suite, source: vm)
        #expect(!store.showsRemoteBranches)

        await store.setShowsRemoteBranches(true)
        #expect(store.showsRemoteBranches)
        let key = HistoryStore.remoteBranchesKey(for: urlA)
        #expect(suite.defaults.bool(forKey: key))
        #expect(Self.makeStore(urlA, defaults: suite, source: vm).showsRemoteBranches)
        #expect(!Self.makeStore(urlB, defaults: suite, source: vm).showsRemoteBranches)

        await store.setShowsRemoteBranches(false)
        #expect(!suite.defaults.bool(forKey: key))
        #expect(!Self.makeStore(urlA, defaults: suite, source: vm).showsRemoteBranches)
    }

    @Test("The toggle's key is the standardized path of the repository")
    func toggleKey() {
        let url = URL(fileURLWithPath: "/var/empty/a/../repo")
        #expect(HistoryStore.remoteBranchesKey(for: url) == "gitForge.history.remoteBranches./var/empty/repo")
    }

    @Test("With the toggle on, the scope loads every remote branch")
    func toggleScope() {
        let suite = TestDefaults()
        defer { suite.remove() }
        let vm = Self.makeVM()
        vm.refs = [GraphFixture.local("main", "m", head: true, upstream: "origin/main", ahead: 0, behind: 0),
                   GraphFixture.remote("origin/main", "m"),
                   GraphFixture.remote("origin/release/2.0", "r"),
                   GraphFixture.remote("fork/topic", "t")]
        let url = Self.missingRepositoryURL()
        let off = Self.makeStore(url, defaults: suite, source: vm)
        #expect(!off.currentScope().includesAllRemotes)
        #expect(off.graphScope() == ["HEAD", "--tags"])

        suite.defaults.set(true, forKey: HistoryStore.remoteBranchesKey(for: url))
        let on = Self.makeStore(url, defaults: suite, source: vm)
        #expect(on.currentScope().includesAllRemotes)
        #expect(on.currentScope().remoteTips == ["origin/main": "m", "origin/release/2.0": "r", "fork/topic": "t"])
        // Each sha once, in the order of the branch names.
        #expect(on.graphScope() == ["HEAD", "t", "m", "r", "--tags"])
    }

    @Test("Setting the same value doesn't reload the log")
    func toggleSameValue() async {
        let suite = TestDefaults()
        defer { suite.remove() }
        let store = Self.makeStore(Self.missingRepositoryURL(), defaults: suite, source: Self.makeVM())
        let before = store.logGen
        await store.setShowsRemoteBranches(false)
        #expect(store.logGen == before)
        await store.setShowsRemoteBranches(true)
        #expect(store.logGen == before &+ 1)
        await store.setShowsRemoteBranches(true)
        #expect(store.logGen == before &+ 1)
        await store.setShowsRemoteBranches(false)
        #expect(store.logGen == before &+ 2)
    }

    @Test("A page appended to a log keeps the log's scope; purge forgets it")
    func appendKeepsScope() {
        let vm = Self.makeVM()
        vm.refs = [GraphFixture.local("main", "m", head: true, upstream: "origin/main", ahead: 0, behind: 1),
                   GraphFixture.remote("origin/main", "u2")]
        vm.history.replaceLog(with: GraphFixture.commits("u2 m\nm a"))
        let scope = vm.history.loadedScope
        vm.refs = [GraphFixture.local("main", "m", head: true, upstream: "origin/main", ahead: 0, behind: 2),
                   GraphFixture.remote("origin/main", "u3")]
        vm.history.appendPage(GraphFixture.commits("a"))
        #expect(vm.history.loadedScope == scope)
        #expect(vm.history.isScopeStale)
        vm.history.purge()
        #expect(vm.history.loadedScope == nil && !vm.history.isScopeStale)
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

    // MARK: Ref chips

    /// `u` (a remote branch's tip) and `p` (an old PR's) on top of `m`, as a first page.
    private static let chipCommits = GraphFixture.commits("u m\np a\nm a\na")

    /// `main` behind `origin/main`, and `origin/old-pr` that no local branch tracks.
    private static let untrackedRefs = [GraphFixture.local("main", "m", head: true, upstream: "origin/main", ahead: 0, behind: 1),
                                        GraphFixture.remote("origin/main", "u"), GraphFixture.remote("origin/old-pr", "p")]

    /// The same, with `topic` tracking `origin/old-pr`.
    private static let trackedRefs = untrackedRefs
        + [GraphFixture.local("topic", "p", upstream: "origin/old-pr", ahead: 0, behind: 0)]

    @Test("The chips are published with the graph and follow the loaded scope's toggle")
    func chipsWithGraph() async {
        let vm = Self.makeVM()
        vm.refs = Self.untrackedRefs
        vm.headSha = "m"
        vm.history.replaceLog(with: Self.chipCommits)
        // Nothing tracks `origin/old-pr`, and the toggle is off.
        #expect(vm.history.refChips.refs(on: "u").map(\.name) == ["origin/main"])
        #expect(vm.history.refChips.refs(on: "p").isEmpty)
        #expect(vm.history.refChips == HistoryRefChips.make(refs: vm.refs, remoteTrunks: vm.history.graphInput().remoteTrunks,
                                                            includesAllRemotes: false))
        let before = vm.history.graphLayouts

        // A branch starts tracking it. Until the layout lands, rows and chips stay as they were.
        let engine = Self.hold(vm, passes: [0])
        vm.refs = Self.trackedRefs
        async let recompute: Void = vm.history.recomputeGraph()
        await engine.gate(0).waiting()
        #expect(vm.history.graphLayouts == before)
        #expect(vm.history.refChips.refs(on: "p").isEmpty)
        engine.gate(0).open()
        await recompute
        #expect(vm.history.refChips.refs(on: "p").map(\.name).sorted() == ["origin/old-pr", "topic"])
        Self.expectPublished(vm.history)
    }

    @Test("A recompute that changes nothing about the chips leaves them as they were")
    func chipsUnchanged() async {
        let vm = Self.makeVM()
        vm.refs = Self.trackedRefs
        vm.history.replaceLog(with: Self.chipCommits)
        let chips = vm.history.refChips
        await vm.history.recomputeGraph()
        #expect(vm.history.refChips == chips)
    }

    @Test("A log fetched with the toggle on shows every remote branch; one fetched with it off keeps hiding them")
    func chipsFollowLoadedScope() async {
        let suite = TestDefaults()
        defer { suite.remove() }
        let vm = Self.makeVM()
        vm.refs = Self.untrackedRefs
        let store = Self.makeStore(Self.missingRepositoryURL(), defaults: suite, source: vm)
        store.replaceLog(with: Self.chipCommits)
        #expect(store.refChips.refs(on: "p").isEmpty)

        // The reload this starts fails (there is no repository), so the old log and its scope stay.
        await store.setShowsRemoteBranches(true)
        await store.recomputeGraph()
        #expect(store.refChips.refs(on: "p").isEmpty)

        // A log fetched with the toggle on has the chips of every remote branch.
        store.replaceLog(with: Self.chipCommits)
        #expect(store.refChips.refs(on: "p").map(\.name) == ["origin/old-pr"])
        await store.recomputeGraph()
        #expect(store.refChips.refs(on: "p").map(\.name) == ["origin/old-pr"])
    }

    @Test("A log laid out again after the refs changed is shown with the chips of the refs it was laid out with")
    func chipsOfTheRelaidInput() async {
        let vm = Self.makeVM()
        vm.refs = Self.untrackedRefs
        vm.headSha = "m"
        let engine = Self.hold(vm, passes: [0])
        async let published = vm.history.publish(vm.history.stageFirstPage(Self.chipCommits))
        await engine.gate(0).waiting()
        // The pass in flight was staged with the old refs; these land before it ends.
        vm.refs = Self.trackedRefs
        await vm.history.recomputeGraph()
        engine.gate(0).open()
        #expect(await published)
        #expect(vm.history.refChips.refs(on: "p").map(\.name).sorted() == ["origin/old-pr", "topic"])
        Self.expectPublished(vm.history)
    }

    /// Swaps in a chips builder that counts its calls; the real one still builds.
    private static func countChipBuilds(_ history: HistoryStore) -> CallCount {
        let builds = CallCount()
        history.refChipsBuilder = { refs, remoteTrunks, includesAllRemotes in
            builds.add()
            return HistoryRefChips.make(refs: refs, remoteTrunks: remoteTrunks, includesAllRemotes: includesAllRemotes)
        }
        return builds
    }

    @Test("The chips are rebuilt only when the refs or the remote trunks change; pages and relayouts reuse them")
    func chipsRebuiltOnlyOnChange() async {
        let vm = Self.makeVM()
        vm.refs = [GraphFixture.local("feature", "f", head: true), GraphFixture.remote("origin/main", "m"),
                   GraphFixture.remote("origin/other", "o")]
        vm.headSha = "f"
        let builds = Self.countChipBuilds(vm.history)
        vm.history.replaceLog(with: GraphFixture.commits("f m\nm o\no"))
        #expect(builds.value == 1)

        // Neither a page, a recompute, a palette change nor a reload of the same refs rebuilds them.
        let chips = vm.history.refChips
        vm.history.appendPage(GraphFixture.commits("z"))
        await vm.history.recomputeGraph()
        await vm.history.setGraphPaletteSize(3)
        vm.history.replaceLog(with: GraphFixture.commits("f m\nm o\no"))
        await vm.history.publish(vm.history.stageFirstPage(GraphFixture.commits("f m\nm o\no")))
        #expect(builds.value == 1)
        #expect(vm.history.refChips == chips)

        // Other remote trunk, same refs.
        vm.remoteHeads = ["origin": "origin/other"]
        await vm.history.recomputeGraph()
        #expect(builds.value == 2)
        await vm.history.recomputeGraph()
        #expect(builds.value == 2)

        // New refs.
        vm.refs += [GraphFixture.tag("v1", "m")]
        await vm.history.recomputeGraph()
        #expect(builds.value == 3)
        #expect(vm.history.refChips.refs(on: "m").map(\.name).contains("v1"))
        vm.history.appendPage(GraphFixture.commits("y"))
        #expect(builds.value == 3)
    }

    @Test("The chips are rebuilt when the loaded scope's toggle changes, and not before")
    func chipsRebuiltWhenToggleChanges() async {
        let suite = TestDefaults()
        defer { suite.remove() }
        let vm = Self.makeVM()
        vm.refs = Self.untrackedRefs
        let store = Self.makeStore(Self.missingRepositoryURL(), defaults: suite, source: vm)
        let builds = Self.countChipBuilds(store)
        store.replaceLog(with: Self.chipCommits)
        #expect(builds.value == 1)
        // The reload this starts fails, so the loaded scope keeps its toggle.
        await store.setShowsRemoteBranches(true)
        await store.recomputeGraph()
        #expect(builds.value == 1)
        store.replaceLog(with: Self.chipCommits)
        #expect(builds.value == 2)
        store.appendPage(GraphFixture.commits("z"))
        #expect(builds.value == 2)
    }

    @Test("Purging the log drops its chips")
    func purgeDropsChips() {
        let vm = Self.makeVM()
        vm.refs = Self.trackedRefs
        vm.history.replaceLog(with: Self.chipCommits)
        #expect(vm.history.refChips != .empty)
        vm.history.purge()
        #expect(vm.history.refChips == .empty)
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

    @Test("loadRefs lays the graph out again only when the refs or HEAD it read differ from the current ones")
    func loadRefsRelayoutsOnlyOnChange() async throws {
        let repo = try await GitTestRepo.make { repo in
            for index in 0..<3 { try repo.commit("c\(index)", files: ["f.txt": "\(index)\n"]) }
        }
        defer { repo.remove() }
        let vm = RepositoryViewModel(repository: Repository(url: repo.url))
        // A published log: with none, a recompute has nothing to lay out.
        vm.history.replaceLog(with: GraphFixture.commits("c b\nb"))
        let engine = Self.hold(vm, passes: [])

        // The first load brings the refs and HEAD in.
        await vm.loadRefs()
        #expect(!vm.refs.isEmpty && vm.headSha != nil)
        #expect(engine.calls == 1)

        // Nothing moved: the same refs and HEAD, so no pass.
        await vm.loadRefs()
        #expect(engine.calls == 1)

        // A new ref.
        try await repo.gitAsync("branch", "topic")
        await vm.loadRefs()
        #expect(engine.calls == 2)

        // HEAD leaves its branch: the refs and HEAD both change.
        try await repo.gitAsync("checkout", "-q", "--detach", "HEAD~1")
        await vm.loadRefs()
        #expect(engine.calls == 3)

        // A detached HEAD moves to another commit: the refs stay and only HEAD changes.
        let refs = vm.refs
        let head = vm.headSha
        try await repo.gitAsync("checkout", "-q", "--detach", "HEAD~1")
        await vm.loadRefs()
        #expect(vm.refs == refs)
        #expect(vm.headSha != head)
        #expect(engine.calls == 4)
    }

    @Test("A loadRefs that reads the same refs during a reload's layout pass adds no pass; one that reads new refs does",
          arguments: [(changesRefs: false, passes: 1), (changesRefs: true, passes: 2)])
    func loadRefsDuringReload(changesRefs: Bool, passes: Int) async throws {
        let repo = try await GitTestRepo.make { try $0.commit("c0", files: ["f.txt": "0\n"]) }
        defer { repo.remove() }
        let vm = RepositoryViewModel(repository: Repository(url: repo.url))
        await vm.loadRefs()
        if changesRefs { try await repo.gitAsync("branch", "topic") }
        let engine = Self.hold(vm, passes: [0])
        async let published = vm.history.publish(vm.history.stageFirstPage(GraphFixture.commits("c b\nb")))
        await engine.gate(0).waiting()
        // `refresh()` reads the refs while the reload is laid out. New ones make the page lay itself out again
        // before it is installed (the recompute adds no pass of its own: no log is published yet); the same
        // ones add nothing.
        await vm.loadRefs()
        engine.gate(0).open()
        #expect(await published)
        #expect(engine.calls == passes)
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
