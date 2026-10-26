import Foundation
import Testing
@testable import gitForge

/// The repository open in gitForge as Team and Mine see it (U1 Rulings 3 and
/// 4): its group first, even when it isn't followed, and its own store the one
/// that opens its pull requests.
@Suite("Pull requests, the open repository")
@MainActor
struct ReviewsStoreActiveTests {
    private static let app = ReviewsHarness.key("team/app")
    private static let api = ReviewsHarness.key("team/api")
    private static let lib = ReviewsHarness.key("oss/lib")

    /// The row id of pull request `number` in the repo with key `repo`.
    private static func id(_ repo: String, _ number: Int) -> InboxPull.ID { "\(repo)#\(number)" }

    /// team/app (a clone) and team/api (activity) read; `marta` is the user.
    /// team/app has !1 by `lucia` and !2 by `marta`; team/api, which is newer,
    /// !3 by `lucia` and !4 by `marta`.
    private static func loaded() async -> (store: ReviewsStore, harness: ReviewsHarness) {
        let harness = ReviewsHarness.twoRepos()
        harness.provider.state {
            $0.lists["team/app"] = [ReviewsHarness.pr(1, by: "lucia", updated: 100),
                                    ReviewsHarness.pr(2, by: "marta", updated: 110)]
            $0.lists["team/api"] = [ReviewsHarness.pr(3, by: "lucia", updated: 300),
                                    ReviewsHarness.pr(4, by: "marta", updated: 310)]
        }
        let store = harness.makeStore()
        await store.refresh(force: true)
        return (store, harness)
    }

    /// oss/lib, which isn't followed: #5 by `lucia`, #6 by `marta`, the older of them.
    private static let libPulls = [ReviewsHarness.pr(5, by: "lucia", updated: 50),
                                   ReviewsHarness.pr(6, by: "marta", updated: 60)]

    /// A repository open with no remote: its store resolves no host.
    private static func withoutRemote() async -> ActiveRepositoryPulls {
        let store = PullRequestStore(cli: nil, auth: { _, _ in .token("t") }, resolveHost: { nil },
                                     makeProvider: { _ in ReviewsFakeProvider() })
        await store.load()
        return ActiveRepositoryPulls(localURL: URL(fileURLWithPath: "/r/none"), store: store)
    }

    // MARK: The repo open, followed or not

    @Test("A followed repo that's open goes first in Team and in Mine; with none open the order is today's")
    func followedActiveFirst() async {
        let (store, harness) = await Self.loaded()
        #expect(store.groups.map(\.repo.id) == [Self.api, Self.app])
        store.filter = .mine
        #expect(store.groups.map(\.repo.id) == [Self.api, Self.app])

        harness.active = await harness.activeStore("team/app", pulls: [], user: "marta")

        #expect(store.activeRepoKey == Self.app)
        #expect(store.groups.map(\.repo.id) == [Self.app, Self.api])
        store.filter = .team
        #expect(store.groups.map(\.repo.id) == [Self.app, Self.api])
        #expect(store.visitingRepo == nil)
    }

    @Test("A repo that's open without being followed comes first with its own pull requests, split by author")
    func visitingFirst() async throws {
        let (store, harness) = await Self.loaded()
        let active = await harness.activeStore("oss/lib", pulls: Self.libPulls, user: "marta")
        harness.active = active

        let visiting = try #require(store.visitingRepo)
        #expect(visiting.id == Self.lib)
        #expect(visiting.sources.isEmpty)
        #expect(visiting.localURL == active.localURL)
        #expect(visiting.cloneURL == "https://gitlab.example.test/oss/lib.git")
        #expect(visiting.accountId == harness.account.id)
        #expect(!store.repos.contains { $0.id == Self.lib })

        #expect(store.groups.map(\.repo.id) == [Self.lib, Self.api, Self.app])
        #expect(store.groups.first?.pulls.map(\.pull.number) == [5])
        #expect(store.groups.first?.error == nil)
        store.filter = .mine
        #expect(store.groups.map(\.repo.id) == [Self.lib, Self.api, Self.app])
        #expect(store.groups.first?.pulls.map(\.pull.number) == [6])
    }

    @Test("The repo that's open without being followed doesn't count for the sidebar")
    func visitingNotCounted() async {
        let (store, harness) = await Self.loaded()
        let before = store.badgeCount
        #expect(before == 2)

        harness.active = await harness.activeStore("oss/lib", pulls: Self.libPulls, user: "marta")

        #expect(store.badgeCount == before)
    }

    @Test("A repo that's open and hidden stays out of Team and Mine")
    func hiddenVisitingLeft() async {
        let (store, harness) = await Self.loaded()
        harness.active = await harness.activeStore("oss/lib", pulls: Self.libPulls, user: "marta")
        #expect(store.visitingRepo != nil)

        await store.hide(ReviewsHarness.host("oss/lib"))

        #expect(store.visitingRepo == nil)
        #expect(!store.groups.contains { $0.repo.id == Self.lib })
        store.filter = .mine
        #expect(!store.groups.contains { $0.repo.id == Self.lib })
        #expect(!store.searchablePulls.contains { $0.repo.id == Self.lib })
    }

    @Test("A repo that's open with no remote gives Team and Mine no group of its own")
    func noHostNoVisiting() async {
        let (store, harness) = await Self.loaded()
        harness.active = await Self.withoutRemote()

        #expect(store.activeRepoKey == nil)
        #expect(store.visitingRepo == nil)
        #expect(store.groups.map(\.repo.id) == [Self.api, Self.app])
        store.filter = .mine
        #expect(store.groups.map(\.repo.id) == [Self.api, Self.app])
    }

    @Test("A repo that's open on an instance with no account is not shown")
    func noAccountOnInstance() async {
        let (store, harness) = await Self.loaded()

        harness.active = await harness.activeStore("oss/lib", pulls: Self.libPulls, user: "marta",
                                                   on: HostingInstance.gitHubDotCom)

        #expect(store.activeRepoKey == "github.com/oss/lib")
        #expect(store.visitingRepo == nil)
        #expect(store.groups.map(\.repo.id) == [Self.api, Self.app])
    }

    @Test("With the login of the open repo still unread its pull requests are Team's and none is Mine's")
    func unknownLoginAllTeam() async {
        let (store, harness) = await Self.loaded()
        let before = store.badgeCount

        harness.active = await harness.activeStore("oss/lib", pulls: Self.libPulls, user: nil)

        #expect(harness.active?.store.currentUser == nil)
        #expect(store.groups.first?.repo.id == Self.lib)
        #expect(store.groups.first?.pulls.map(\.pull.number) == [6, 5])
        store.filter = .mine
        #expect(!store.groups.contains { $0.repo.id == Self.lib })
        #expect(store.badgeCount == before)
    }

    @Test("The author is matched with the login of the open repo in any case")
    func loginMatchIgnoresCase() async {
        let (store, harness) = await Self.loaded()

        harness.active = await harness.activeStore("oss/lib", pulls: Self.libPulls, user: "Marta")

        #expect(store.groups.first?.pulls.map(\.pull.number) == [5])
        store.filter = .mine
        #expect(store.groups.first?.pulls.map(\.pull.number) == [6])
    }

    @Test("Moving to another repo drops the old one's group and a selection on its row, and the new one comes first")
    func switchingRepoDropsVisitingSelection() async {
        let (store, harness) = await Self.loaded()
        harness.active = await harness.activeStore("oss/lib", pulls: Self.libPulls, user: "marta")
        store.selectedID = Self.id(Self.lib, 5)
        #expect(store.selectedItem?.pull.number == 5)

        harness.active = await harness.activeStore("team/app", pulls: [], user: "marta")
        store.dropHiddenSelection()

        #expect(store.selectedItem == nil)
        #expect(store.selectedID == nil)
        #expect(store.groups.first?.repo.id == Self.app)
        #expect(!store.groups.contains { $0.repo.id == Self.lib })
    }

    @Test("A followed repo that's open with its own store loaded is one group, and its rows are searched once")
    func noDuplicates() async {
        let (store, harness) = await Self.loaded()
        let appPulls = harness.provider.state { $0.lists["team/app"] } ?? []
        harness.active = await harness.activeStore("team/app", pulls: appPulls, user: "marta")

        #expect(store.groups.filter { $0.repo.id == Self.app }.count == 1)
        store.filter = .mine
        #expect(store.groups.filter { $0.repo.id == Self.app }.count == 1)
        let ids = store.searchablePulls.map(\.id)
        #expect(ids.count == 4)
        #expect(Set(ids).count == ids.count)
    }

    // MARK: ⌘K and the inbox's actions

    @Test("The open repo's pull requests are searched and revealed, in the half that shows them")
    func visitingSearchableAndRevealable() async {
        let (store, harness) = await Self.loaded()
        harness.active = await harness.activeStore("oss/lib", pulls: Self.libPulls, user: "marta")
        let lucia = Self.id(Self.lib, 5)
        let marta = Self.id(Self.lib, 6)
        #expect(store.searchablePulls.map(\.id).contains(lucia))
        #expect(store.searchablePulls.map(\.id).contains(marta))
        store.filter = .mine

        #expect(store.reveal(lucia))
        #expect(store.filter == .team)
        #expect(store.selectedItem?.id == lucia)
        #expect(store.revealRequest?.id == lucia)

        #expect(store.reveal(marta))
        #expect(store.filter == .mine)
        #expect(store.selectedItem?.id == marta)
    }

    @Test("Narrowed to a repo, the inbox leaves the open repo's group out, but ⌘K still finds its rows")
    func narrowedHidesVisiting() async {
        let (store, harness) = await Self.loaded()
        harness.active = await harness.activeStore("oss/lib", pulls: Self.libPulls, user: "marta")

        store.showRepo(Self.api)

        #expect(store.groups.map(\.repo.id) == [Self.api])
        #expect(store.searchablePulls.contains { $0.repo.id == Self.lib })
    }

    @Test("Closing the repo filter with a row of the open repo selected goes to the half that shows it")
    func closingFilterOnVisitingRow() async {
        let (store, harness) = await Self.loaded()
        harness.active = await harness.activeStore("oss/lib", pulls: Self.libPulls, user: "marta")
        store.showRepo(Self.api)
        store.selectedID = Self.id(Self.lib, 6)

        store.showAllRepos()

        #expect(store.repoFilter == nil)
        #expect(store.filter == .mine)
        #expect(store.selectedID == Self.id(Self.lib, 6))
        #expect(store.revealRequest?.id == Self.id(Self.lib, 6))
    }

    @Test("An Other that's a row of the open repo isn't listed twice, nor searched twice")
    func otherOfVisitingNotDuplicated() async {
        let (store, harness) = await Self.loaded()
        harness.provider.state { $0.lists["oss/lib"] = Self.libPulls }
        let link = PullRequestLink(host: ReviewsHarness.host("oss/lib"), number: 5,
                                   instanceId: ReviewsHarness.instance.id)
        let id = Self.id(Self.lib, 5)
        #expect(await store.openLink(link) == .opened(id))
        #expect(store.others.map(\.id) == [id])
        store.selectedID = nil
        #expect(store.visibleOthers.map(\.id) == [id])

        harness.active = await harness.activeStore("oss/lib", pulls: Self.libPulls, user: "marta")

        #expect(store.visibleOthers.isEmpty)
        #expect(store.searchablePulls.filter { $0.id == id }.count == 1)
        #expect(store.groups.first?.pulls.map(\.id) == [id])
    }

    // MARK: Detail

    @Test("The detail action is the repo's own local one for the open repo, and clone or open for the rest")
    func detailActionByRepo() async throws {
        let (store, harness) = await Self.loaded()
        let appItem = try #require(store.inboxRows.first { $0.id == Self.id(Self.app, 1) })
        let apiItem = try #require(store.inboxRows.first { $0.id == Self.id(Self.api, 3) })
        #expect(store.detailAction(for: appItem) == .repo(.openInRepository(URL(fileURLWithPath: "/r/team/app"))))

        harness.active = await harness.activeStore("team/app", pulls: [], user: "marta")
        #expect(store.isActive(appItem.repo))
        #expect(!store.isActive(apiItem.repo))
        #expect(store.detailAction(for: appItem) == .local)

        harness.active = await harness.activeStore("oss/lib", pulls: Self.libPulls, user: "marta")
        #expect(store.detailAction(for: appItem) == .repo(.openInRepository(URL(fileURLWithPath: "/r/team/app"))))
        #expect(store.detailAction(for: apiItem) == .repo(.clone(url: apiItem.repo.cloneURL)))
        let libItem = try #require(store.inboxRows.first { $0.id == Self.id(Self.lib, 5) })
        #expect(store.detailAction(for: libItem) == .local)
    }

    @Test("The open repo's pull requests open in its own store, once, whether it's followed or not")
    func activeDetailIsRepositoryStore() async throws {
        let (store, harness) = await Self.loaded()
        let active = await harness.activeStore("oss/lib", pulls: Self.libPulls, user: "marta")
        harness.active = active
        #expect(store.detailStore(for: Self.lib) === active.store)
        #expect(store.detailStore(for: Self.app) !== active.store)

        let five = try #require(store.inboxRows.first { $0.id == Self.id(Self.lib, 5) })
        await store.open(five)
        #expect(active.store.selected?.number == 5)
        await waitUntil { active.store.detail != nil && !active.store.isLoadingDetail }

        // Already open, as the repo's Open tab has it: nothing is read again.
        let gen = active.store.detailGen
        await store.open(five)
        #expect(active.store.detailGen == gen)
        #expect(active.store.selected?.number == 5)

        let six = try #require(store.inboxRows.first { $0.id == Self.id(Self.lib, 6) })
        await store.open(six)
        #expect(active.store.selected?.number == 6)
        #expect(active.store.detailGen != gen)

        let followed = await harness.activeStore("team/app", pulls: [], user: "marta")
        harness.active = followed
        #expect(store.detailStore(for: Self.app) === followed.store)
        #expect(store.detailStore(for: Self.lib) == nil)
    }
}
