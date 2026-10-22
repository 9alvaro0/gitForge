import SwiftUI
import Testing
@testable import gitForge

/// Which refs History draws as chips, and how (graph v3 spec §4.4).
@Suite("HistoryRefChips")
struct HistoryRefChipsTests {

    @Test("Without every remote, only tracked remotes and remote trunks get chips")
    func shownRemotes() {
        let refs = [GraphFixture.local("main", "m", upstream: "origin/main", ahead: 0, behind: 1),
                    GraphFixture.remote("origin/main", "u"), GraphFixture.remote("origin/old-pr", "p"),
                    GraphFixture.remote("origin/develop", "d"), GraphFixture.tag("v1", "p")]
        let chips = HistoryRefChips.make(refs: refs, remoteTrunks: ["origin/develop": 1], includesAllRemotes: false)
        #expect(chips.refs(on: "u").map(\.name) == ["origin/main"])
        #expect(chips.refs(on: "p").map(\.name) == ["v1"])
        #expect(chips.refs(on: "d").map(\.name) == ["origin/develop"])
        #expect(HistoryRefChips.make(refs: refs, remoteTrunks: [:], includesAllRemotes: true)
                .refs(on: "p").map(\.name).sorted() == ["origin/old-pr", "v1"])
    }

    @Test("Local branches and tags always get their chips; a commit without refs has none")
    func localsAndTags() {
        let refs = [GraphFixture.local("feature", "f"), GraphFixture.tag("v1", "f"), GraphFixture.remote("origin/x", "x")]
        let chips = HistoryRefChips.make(refs: refs, remoteTrunks: [:], includesAllRemotes: false)
        #expect(chips.refs(on: "f").map(\.name) == ["feature", "v1"])
        #expect(chips.refs(on: "x").isEmpty)
        #expect(chips.refs(on: "nowhere").isEmpty)
    }

    @Test("A remote is away from its local when they point at different commits")
    func away() {
        let refs = [GraphFixture.local("a", "x", upstream: "origin/a", ahead: 0, behind: 1), GraphFixture.remote("origin/a", "y"),
                    GraphFixture.local("b", "z", upstream: "origin/b", ahead: 0, behind: 0), GraphFixture.remote("origin/b", "z"),
                    GraphFixture.remote("origin/c", "w")]
        let chips = HistoryRefChips.make(refs: refs, remoteTrunks: [:], includesAllRemotes: true)
        #expect(chips.awayFromLocal == ["origin/a"])
        #expect(chips.isDashed(GraphFixture.remote("origin/c", "w"), onGhost: true))
        #expect(!chips.isDashed(GraphFixture.remote("origin/c", "w"), onGhost: false))
        #expect(!chips.isDashed(GraphFixture.local("a", "x"), onGhost: true))
    }

    @Test("A remote is dashed when it is away from its local branch, solid when it is on the commit of one of them")
    func dashedByLocal() {
        let refs = [GraphFixture.local("a", "x", upstream: "origin/a", ahead: 0, behind: 1), GraphFixture.remote("origin/a", "y"),
                    GraphFixture.local("b", "z", upstream: "origin/b", ahead: 0, behind: 0), GraphFixture.remote("origin/b", "z"),
                    // Two local branches track it: one is on its commit.
                    GraphFixture.local("c1", "c", upstream: "origin/c", ahead: 0, behind: 0),
                    GraphFixture.local("c2", "k", upstream: "origin/c", ahead: 0, behind: 2),
                    GraphFixture.remote("origin/c", "c")]
        let chips = HistoryRefChips.make(refs: refs, remoteTrunks: [:], includesAllRemotes: false)
        #expect(chips.isDashed(GraphFixture.remote("origin/a", "y"), onGhost: false))
        #expect(!chips.isDashed(GraphFixture.remote("origin/b", "z"), onGhost: false))
        #expect(!chips.isDashed(GraphFixture.remote("origin/c", "c"), onGhost: false))
        // On a ghost commit it is dashed whatever its local branch does.
        #expect(chips.isDashed(GraphFixture.remote("origin/b", "z"), onGhost: true))
        // Tags have no remote to be away from.
        #expect(!chips.isDashed(GraphFixture.tag("v1", "z"), onGhost: true))
    }

    @Test("The remote prefix shows only when two remotes with chips share a branch name")
    func prefix() {
        let refs = [GraphFixture.local("main", "m", upstream: "origin/main", ahead: 0, behind: 0),
                    GraphFixture.remote("origin/main", "m"), GraphFixture.remote("fork/main", "f")]
        let all = HistoryRefChips.make(refs: refs, remoteTrunks: [:], includesAllRemotes: true)
        #expect(all.prefixed == ["origin/main", "fork/main"])
        #expect(all.label(for: GraphFixture.remote("fork/main", "f")) == "fork/main")
        let tracked = HistoryRefChips.make(refs: refs, remoteTrunks: [:], includesAllRemotes: false)
        #expect(tracked.prefixed.isEmpty)
        #expect(tracked.label(for: GraphFixture.remote("origin/main", "m")) == "main")
    }

    @Test("Labels: the short name, except a prefixed remote branch, which keeps its remote")
    func labels() {
        let refs = [GraphFixture.local("feature/x", "a"), GraphFixture.tag("v1.0", "a"),
                    GraphFixture.remote("origin/feature/x", "b"), GraphFixture.remote("origin/solo", "c"),
                    GraphFixture.remote("origin/shared", "d"), GraphFixture.remote("fork/shared", "e")]
        let chips = HistoryRefChips.make(refs: refs, remoteTrunks: [:], includesAllRemotes: true)
        // A local branch with the name of a remote one doesn't prefix it: only remotes count.
        #expect(chips.prefixed == ["origin/shared", "fork/shared"])
        #expect(chips.label(for: GraphFixture.local("feature/x", "a")) == "feature/x")
        #expect(chips.label(for: GraphFixture.tag("v1.0", "a")) == "v1.0")
        #expect(chips.label(for: GraphFixture.remote("origin/feature/x", "b")) == "feature/x")
        #expect(chips.label(for: GraphFixture.remote("origin/solo", "c")) == "solo")
        #expect(chips.label(for: GraphFixture.remote("origin/shared", "d")) == "origin/shared")
    }

    @Test("A remote branch hidden by the toggle doesn't count towards the prefix")
    func hiddenRemoteDoesNotPrefix() {
        let refs = [GraphFixture.local("a", "a", upstream: "origin/shared", ahead: 0, behind: 0),
                    GraphFixture.remote("origin/shared", "a"), GraphFixture.remote("fork/shared", "f")]
        #expect(HistoryRefChips.make(refs: refs, remoteTrunks: [:], includesAllRemotes: false).prefixed.isEmpty)
        #expect(HistoryRefChips.make(refs: refs, remoteTrunks: ["fork/shared": 1], includesAllRemotes: false)
                    .prefixed == ["origin/shared", "fork/shared"])
    }

    @Test("Refs on a commit keep the order they were read in")
    func keepsOrder() {
        let refs = [GraphFixture.tag("v2", "c"), GraphFixture.local("b", "c"), GraphFixture.local("a", "c")]
        let chips = HistoryRefChips.make(refs: refs, remoteTrunks: [:], includesAllRemotes: false)
        #expect(chips.refs(on: "c").map(\.name) == ["v2", "b", "a"])
    }

    @Test("No refs, no chips")
    func empty() {
        #expect(HistoryRefChips.make(refs: [], remoteTrunks: [:], includesAllRemotes: true) == .empty)
        #expect(HistoryRefChips.empty.refs(on: "x").isEmpty)
        #expect(HistoryRefChips.empty.label(for: GraphFixture.remote("origin/x", "x")) == "x")
    }

    // MARK: Order of a commit's chips

    /// Chip names on `sha`, in the order `CommitRowChips` draws them.
    @MainActor
    private static func order(on sha: String, _ chips: HistoryRefChips) -> [String] {
        CommitRowChips.ordered(chips.refs(on: sha), currentBranch: "main", chips: chips).map(\.name)
    }

    @MainActor
    @Test("A remote a local branch tracks comes before an untracked one on its commit, whatever the read order",
          arguments: [true, false])
    func trackedRemoteFirst(trackedFirst: Bool) {
        let remotes = [GraphFixture.remote("origin/feature/cart", "c"), GraphFixture.remote("fork/feature/cart", "c")]
        let refs = [GraphFixture.local("main", "m", head: true),
                    GraphFixture.local("feature/cart", "l", upstream: "origin/feature/cart", ahead: 1, behind: 1)]
            + (trackedFirst ? remotes : remotes.reversed())
        let chips = HistoryRefChips.make(refs: refs, remoteTrunks: [:], includesAllRemotes: true)
        #expect(Self.order(on: "c", chips) == ["origin/feature/cart", "fork/feature/cart"])
    }

    @MainActor
    @Test("A remote trunk comes before an untracked remote on its commit, whatever the read order",
          arguments: [true, false])
    func remoteTrunkFirst(trunkFirst: Bool) {
        let remotes = [GraphFixture.remote("origin/main", "c"), GraphFixture.remote("fork/api", "c")]
        let refs = [GraphFixture.local("feature", "f", head: true), GraphFixture.tag("v1", "c")]
            + (trunkFirst ? remotes : remotes.reversed())
        let chips = HistoryRefChips.make(refs: refs, remoteTrunks: ["origin/main": 0], includesAllRemotes: true)
        #expect(Self.order(on: "c", chips) == ["v1", "origin/main", "fork/api"])
    }

    // MARK: Look of a commit's chips

    @Test("A commit's look is its refs with their label and away flag; other commits' refs don't enter it")
    func look() {
        let refs = [GraphFixture.local("a", "x", upstream: "origin/a", ahead: 0, behind: 1), GraphFixture.remote("origin/a", "y"),
                    GraphFixture.remote("origin/s", "y"), GraphFixture.remote("fork/s", "f")]
        let chips = HistoryRefChips.make(refs: refs, remoteTrunks: [:], includesAllRemotes: true)
        #expect(chips.look(on: "y").map(\.ref.name) == ["origin/a", "origin/s"])
        #expect(chips.look(on: "y").map(\.label) == ["a", "origin/s"])
        #expect(chips.look(on: "y").map(\.isAway) == [true, false])
        #expect(chips.look(on: "nowhere").isEmpty)

        let other = HistoryRefChips.make(refs: refs + [GraphFixture.tag("v1", "z"), GraphFixture.local("b", "z")],
                                         remoteTrunks: [:], includesAllRemotes: true)
        #expect(other.look(on: "y") == chips.look(on: "y"))
    }

    /// A row for the first sample commit with `chips`.
    @MainActor
    private static func row(_ chips: HistoryRefChips) -> CommitRow {
        CommitRow(commit: Commit.previewSamples[0], layout: .empty, maxLanes: 1, rowHeight: 28,
                  tableLayout: HistoryTableLayout(viewport: 1100, graph: 80, author: 112, date: 92, commit: 64),
                  chips: chips, currentBranch: nil, isSelected: false, dimmed: false,
                  onSelect: {}, onDoubleClick: {}, onBranchDrop: nil)
    }

    @MainActor private static let sha = Commit.previewSamples[0].sha

    @MainActor
    @Test("Rows are equal while only refs of other commits change, so the table doesn't redraw them")
    func rowEqualityIgnoresOtherCommits() {
        let own = [GraphFixture.local("a", Self.sha, upstream: "origin/a", ahead: 1, behind: 0),
                   GraphFixture.remote("origin/a", Self.sha)]
        func chips(_ others: [GitRef]) -> HistoryRefChips {
            .make(refs: own + others, remoteTrunks: [:], includesAllRemotes: true)
        }
        #expect(Self.row(chips([])) == Self.row(chips([GraphFixture.tag("v1", "elsewhere")])))
        #expect(Self.row(chips([GraphFixture.local("b", "e1", upstream: "origin/b", ahead: 0, behind: 1),
                                GraphFixture.remote("origin/b", "e2")]))
                == Self.row(chips([GraphFixture.local("c", "e3", upstream: "origin/c", ahead: 4, behind: 0),
                                   GraphFixture.remote("origin/c", "e4"), GraphFixture.tag("v2", "e5")])))
    }

    @MainActor
    @Test("Rows are not equal when a ref on their own commit changes, so the table redraws them")
    func rowEqualityCoversOwnChips() {
        let remote = GraphFixture.remote("origin/a", Self.sha)
        func chips(local: GitRef, extra: [GitRef] = []) -> HistoryRefChips {
            .make(refs: [local, remote] + extra, remoteTrunks: [:], includesAllRemotes: true)
        }
        let local = GraphFixture.local("a", Self.sha, upstream: "origin/a", ahead: 1, behind: 0)
        let base = Self.row(chips(local: local))
        #expect(base == Self.row(chips(local: local)))
        // A counter changes.
        #expect(base != Self.row(chips(local: GraphFixture.local("a", Self.sha, upstream: "origin/a", ahead: 2, behind: 0))))
        // The remote becomes away from its local branch.
        #expect(base != Self.row(chips(local: GraphFixture.local("a", "elsewhere", upstream: "origin/a", ahead: 1, behind: 0))))
        // A ref arrives on the commit.
        #expect(base != Self.row(chips(local: local, extra: [GraphFixture.tag("v1", Self.sha)])))
        // Another remote shares the name of one on the commit, which then shows its prefix.
        #expect(base != Self.row(chips(local: local, extra: [GraphFixture.remote("fork/a", "elsewhere")])))
    }

    @MainActor
    @Test("Rows are not equal when a remote on their commit starts leading the others, so the chips reorder")
    func rowEqualityCoversRemoteOrder() {
        let refs = [GraphFixture.remote("origin/main", Self.sha), GraphFixture.remote("fork/api", Self.sha)]
        #expect(Self.row(.make(refs: refs, remoteTrunks: [:], includesAllRemotes: true))
                != Self.row(.make(refs: refs, remoteTrunks: ["origin/main": 0], includesAllRemotes: true)))
    }
}
