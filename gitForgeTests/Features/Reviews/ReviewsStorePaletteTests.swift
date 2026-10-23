import Foundation
import Testing
@testable import gitForge

/// What ⌘K reads from the inbox (R2 Rulings 6, 7 and 8): the repo filter,
/// picking a row from outside, the pull requests to search and the repos
/// that aren't on this Mac.
@Suite("Reviews store, what the palette reads")
@MainActor
struct ReviewsStorePaletteTests {
    private static let api = ReviewsHarness.key("team/api")
    private static let app = ReviewsHarness.key("team/app")
    private static let unknown = "gitlab.example.test/none/repo"

    /// The row id of pull request `number` in the repo with key `repo`.
    private static func id(_ repo: String, _ number: Int) -> InboxPull.ID { "\(repo)#\(number)" }

    /// team/app (a clone) and team/api (activity) read, with five pull
    /// requests from `marta` (the user) and `octo`, a draft among them. Newest
    /// first: 5 (draft, api), 3 (app), 2 (api), 1 (api), 4 (app).
    private static func loaded() async -> (store: ReviewsStore, harness: ReviewsHarness) {
        let harness = ReviewsHarness.twoRepos()
        harness.provider.state {
            $0.lists["team/api"] = [ReviewsHarness.pr(1, by: "octo", updated: 100),
                                    ReviewsHarness.pr(2, by: "marta", updated: 200),
                                    ReviewsHarness.pr(5, by: "octo", state: .draft, updated: 500)]
            $0.lists["team/app"] = [ReviewsHarness.pr(3, by: "octo", updated: 300),
                                    ReviewsHarness.pr(4, by: "marta", updated: 50)]
        }
        let store = harness.makeStore()
        await store.refresh(force: true)
        return (store, harness)
    }

    @Test("Showing a repo lists all its pull requests, the user's and the others', and no other repo's")
    func repoFilter() async {
        let (store, _) = await Self.loaded()
        #expect(store.repoFilter == nil)
        #expect(store.filteredRepo == nil)
        #expect(store.groups.map(\.repo.id) == [Self.api, Self.app])

        store.showRepo(Self.api)

        #expect(store.repoFilter == Self.api)
        #expect(store.filteredRepo?.id == Self.api)
        #expect(store.groups.map(\.repo.id) == [Self.api])
        #expect(store.groups.first?.pulls.map(\.pull.number) == [5, 2, 1])
        #expect(store.groups.first?.pulls.map(\.pull.authorLogin) == ["octo", "marta", "octo"])
        // The half is the user's to choose: showing a repo doesn't move it.
        #expect(store.filter == .team)

        // A repo that isn't followed can't be shown.
        store.showRepo(Self.unknown)
        #expect(store.repoFilter == Self.api)
        #expect(store.groups.map(\.repo.id) == [Self.api])
    }

    @Test("A key that isn't followed filters nothing")
    func repoFilterIgnoresUnknownRepos() async {
        let (store, _) = await Self.loaded()
        store.filter = .mine
        store.selectedID = Self.id(Self.app, 4)

        store.showRepo(Self.unknown)

        #expect(store.repoFilter == nil)
        #expect(store.filteredRepo == nil)
        #expect(store.filter == .mine)
        #expect(store.selectedID == Self.id(Self.app, 4))
        #expect(store.groups.map(\.repo.id) == [Self.api, Self.app])
    }

    @Test("The filtered repo that failed to read shows its error, and the others show nothing")
    func repoFilterKeepsItsError() async {
        let (store, harness) = await Self.loaded()
        harness.provider.state { $0.failures["team/api"] = .notFound }
        await store.refresh(force: true)

        store.showRepo(Self.api)

        #expect(store.groups.map(\.repo.id) == [Self.api])
        #expect(store.groups.first?.pulls.isEmpty == true)
        #expect(store.groups.first?.error == PullRequestStore.message(for: PullRequestFetchError.notFound))
    }

    @Test("Narrowed to a repo known to be empty, a refresh shows the empty state while another repo is still unread")
    func repoFilterEmptyNotLoading() async {
        let harness = ReviewsHarness.twoRepos()
        // No activity in team/api yet: only the clone is followed, and it has nothing open.
        harness.activity.state { $0.hits = [] }
        let store = harness.makeStore()
        await store.refresh(force: true)
        store.showRepo(Self.app)
        #expect(store.listContent == .empty)

        // The next round adopts team/api, whose read is still on its way.
        let reading = AsyncGate()
        harness.activity.state { $0.hits = [ActivityHit(ref: .projectId("2"), at: ReviewsHarness.date(1_789_000_000))] }
        harness.provider.state {
            $0.lists["team/api"] = [ReviewsHarness.pr(2, by: "octo", updated: 200)]
            $0.gates["team/api"] = reading
        }
        let round = Task { await store.refresh(force: true) }
        await reading.waiting()
        #expect(store.isRefreshing)
        #expect(store.pulls[Self.api] == nil)
        #expect(store.listContent == .empty)
        // The whole inbox does wait for team/api.
        store.showAllRepos()
        #expect(store.listContent == .loading)

        reading.open()
        await round.value
    }

    @Test("Showing a repo keeps the selection if it's one of its pull requests, whichever half, and drops it if not")
    func repoFilterKeepsSelectionInRepo() async {
        let (store, _) = await Self.loaded()

        // The user's own, with Team on: the repo's view shows both halves.
        let own = Self.id(Self.api, 2)
        store.selectedID = own
        store.showRepo(Self.api)
        #expect(store.selectedID == own)
        #expect(store.selectedItem?.id == own)

        store.showAllRepos()
        store.selectedID = Self.id(Self.app, 3)
        store.showRepo(Self.api)
        #expect(store.selectedID == nil)
        #expect(store.selectedItem == nil)
    }

    @Test("Showing every repo again keeps a selection picked while narrowed: the inbox moves to the half that shows it")
    func showAllReposKeepsSelection() async {
        let (store, _) = await Self.loaded()
        #expect(store.filter == .team)

        // The user's own, picked in the repo's view with Team on.
        let own = Self.id(Self.api, 2)
        store.showRepo(Self.api)
        store.selectedID = own
        store.showAllRepos()

        #expect(store.repoFilter == nil)
        #expect(store.filter == .mine)
        #expect(store.selectedID == own)
        #expect(store.selectedItem?.id == own)

        // A teammate's, picked with Mine on.
        let teammate = Self.id(Self.api, 1)
        store.showRepo(Self.api)
        store.selectedID = teammate
        store.showAllRepos()

        #expect(store.repoFilter == nil)
        #expect(store.filter == .team)
        #expect(store.selectedID == teammate)
        #expect(store.selectedItem?.id == teammate)
    }

    @Test("Showing every repo again with nothing selected only drops the filter")
    func showAllReposWithoutSelection() async {
        let (store, _) = await Self.loaded()
        store.filter = .mine
        store.showRepo(Self.api)

        store.showAllRepos()

        #expect(store.repoFilter == nil)
        #expect(store.filteredRepo == nil)
        #expect(store.filter == .mine)
        #expect(store.selectedID == nil)
        #expect(store.groups.map(\.repo.id) == [Self.api, Self.app])
    }

    @Test("The filter goes when its repo stops being followed, and stays while it is")
    func repoFilterLeaves() async {
        let (store, harness) = await Self.loaded()
        store.showRepo(Self.api)

        await store.refresh(force: true)
        #expect(store.repoFilter == Self.api)
        #expect(store.filteredRepo?.id == Self.api)

        // team/api was followed for the user's activity there: with none, it goes.
        harness.activity.state { $0.hits = [] }
        await store.refresh(force: true)

        #expect(!store.repos.contains { $0.id == Self.api })
        #expect(store.repoFilter == nil)
        #expect(store.filteredRepo == nil)
        #expect(store.groups.map(\.repo.id) == [Self.app])
    }

    @Test("Revealing a row switches to the half that shows it, drops a filter on another repo and selects it")
    func revealSwitchesHalf() async {
        let (store, _) = await Self.loaded()
        #expect(store.filter == .team)

        // The user's own, from Team.
        let own = Self.id(Self.api, 2)
        #expect(store.reveal(own))
        #expect(store.filter == .mine)
        #expect(store.selectedItem?.id == own)

        // Someone else's, from Mine.
        let others = Self.id(Self.app, 3)
        #expect(store.reveal(others))
        #expect(store.filter == .team)
        #expect(store.selectedItem?.id == others)

        // From another repo's view: that view goes.
        store.showRepo(Self.api)
        #expect(store.reveal(others))
        #expect(store.repoFilter == nil)
        #expect(store.selectedItem?.id == others)

        // From its own repo's view, it stays.
        store.showRepo(Self.api)
        let draft = Self.id(Self.api, 5)
        store.filter = .mine
        #expect(store.reveal(draft))
        #expect(store.repoFilter == Self.api)
        #expect(store.filter == .team)
        #expect(store.selectedItem?.id == draft)
    }

    @Test("A selection made or kept from outside the list asks it to scroll to the row, the same row again too; a click doesn't")
    func revealRequests() async throws {
        let (store, _) = await Self.loaded()
        #expect(store.revealRequest == nil)

        let own = Self.id(Self.api, 2)
        store.reveal(own)
        let first = try #require(store.revealRequest)
        #expect(first.id == own)

        store.reveal(own)
        #expect(store.revealRequest?.id == own)
        #expect(store.revealRequest != first)

        // A click: the row is in view already.
        let beforeClick = store.revealRequest
        store.selectedID = Self.id(Self.app, 4)
        #expect(store.revealRequest == beforeClick)

        // Narrowing to its repo keeps the selection, and brings it into view.
        store.showRepo(Self.app)
        let narrowed = try #require(store.revealRequest)
        #expect(narrowed.id == Self.id(Self.app, 4))
        #expect(narrowed != beforeClick)

        // So does showing every repo again, in the half that shows it.
        store.showAllRepos()
        #expect(store.filter == .mine)
        #expect(store.revealRequest?.id == Self.id(Self.app, 4))
        #expect(store.revealRequest != narrowed)

        // Nothing selected, or nothing found: nothing to bring into view.
        store.selectedID = nil
        let idle = store.revealRequest
        store.showRepo(Self.api)
        store.showAllRepos()
        #expect(store.reveal(Self.id(Self.api, 99)) == false)
        #expect(store.revealRequest == idle)
    }

    @Test("Revealing a row that isn't there says no and changes nothing")
    func revealUnknown() async {
        let (store, _) = await Self.loaded()
        store.filter = .mine
        store.showRepo(Self.api)
        let selected = Self.id(Self.api, 2)
        store.selectedID = selected

        #expect(store.reveal("gitlab.example.test/none#1") == false)
        #expect(store.reveal(Self.id(Self.api, 99)) == false)

        #expect(store.filter == .mine)
        #expect(store.repoFilter == Self.api)
        #expect(store.selectedID == selected)
    }

    @Test("The searchable pull requests are all the followed repos' open ones, newest first, whatever the filters")
    func searchablePulls() async {
        let (store, _) = await Self.loaded()
        let newestFirst = [Self.id(Self.api, 5), Self.id(Self.app, 3), Self.id(Self.api, 2),
                           Self.id(Self.api, 1), Self.id(Self.app, 4)]

        #expect(store.searchablePulls.map(\.id) == newestFirst)
        #expect(store.searchablePulls.map(\.pull.authorLogin) == ["octo", "octo", "marta", "octo", "marta"])
        #expect(store.searchablePulls.first { $0.pull.number == 5 }?.pull.state == .draft)

        store.filter = .mine
        store.showRepo(Self.app)
        #expect(store.searchablePulls.map(\.id) == newestFirst)
    }

    @Test("The repos not cloned are the followed ones with no clone on this Mac")
    func unclonedRepos() async {
        let (store, _) = await Self.loaded()
        #expect(store.repos.count == 2)

        #expect(store.unclonedRepos.map(\.id) == [Self.api])
        #expect(store.unclonedRepos.allSatisfy { $0.localURL == nil })
    }
}
