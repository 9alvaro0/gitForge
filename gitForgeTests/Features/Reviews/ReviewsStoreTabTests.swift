import Foundation
import Testing
@testable import gitForge

/// The tab the Pull requests section is on and how it's remembered (U1
/// Ruling 2): the inbox's half and the open repository's list, in one value.
@Suite("Pull requests tab")
@MainActor
struct ReviewsStoreTabTests {
    private static let app = ReviewsHarness.key("team/app")
    private static let api = ReviewsHarness.key("team/api")

    /// The row id of pull request `number` in the repo with key `repo`.
    private static func id(_ repo: String, _ number: Int) -> InboxPull.ID { "\(repo)#\(number)" }

    /// team/app (a clone) and team/api (activity) read: !1 by `lucia` in
    /// team/app, !2 by `marta` (the user) in team/api.
    private static func loaded() async -> (store: ReviewsStore, harness: ReviewsHarness) {
        let harness = ReviewsHarness.twoRepos()
        harness.provider.state {
            $0.lists["team/app"] = [ReviewsHarness.pr(1, by: "lucia", updated: 100)]
            $0.lists["team/api"] = [ReviewsHarness.pr(2, by: "marta", updated: 200)]
        }
        let store = harness.makeStore()
        await store.refresh(force: true)
        return (store, harness)
    }

    // MARK: Remembering

    @Test("With nothing saved the section starts on Team, showing the inbox")
    func startsOnTeam() {
        let store = ReviewsHarness.twoRepos().makeStore()

        #expect(store.tab == .team)
        #expect(store.filter == .team)
        #expect(store.repositoryList == nil)
    }

    @Test("The saved tab comes back: a repository list keeps the half where it was, a half shows the inbox")
    func restoresSaved() {
        let harness = ReviewsHarness.twoRepos()

        harness.savedTab = .closed
        let closed = harness.makeStore()
        #expect(closed.tab == .closed)
        #expect(closed.filter == .team)
        #expect(closed.repositoryList == .closed)

        harness.savedTab = .open
        #expect(harness.makeStore().repositoryList == .open)

        harness.savedTab = .mine
        let mine = harness.makeStore()
        #expect(mine.tab == .mine)
        #expect(mine.filter == .mine)
        #expect(mine.repositoryList == nil)
    }

    @Test("Reading the saved tab saves nothing")
    func loadingDoesNotSave() {
        let harness = ReviewsHarness.twoRepos()
        harness.savedTab = .closed

        _ = harness.makeStore()

        #expect(harness.savedTabs.isEmpty)
    }

    @Test("Every change of tab is saved, however it's made")
    func savesEveryChange() {
        let harness = ReviewsHarness.twoRepos()
        let store = harness.makeStore()

        store.tab = .open
        store.tab = .mine
        store.filter = .team

        #expect(harness.savedTabs == [.open, .mine, .team])
    }

    @Test("A change that leaves the tab as it was saves nothing, and a change saves once")
    func savesOncePerChange() {
        let harness = ReviewsHarness.twoRepos()
        let store = harness.makeStore()

        store.tab = .team
        store.filter = .team
        #expect(harness.savedTabs.isEmpty)

        // From a list to a half moves the list and the half: one value, saved once.
        store.tab = .closed
        store.filter = .mine
        store.tab = .team
        #expect(store.tab == .team)
        #expect(store.filter == .team)
        #expect(harness.savedTabs == [.closed, .team])

        store.tab = .mine
        store.tab = .mine
        #expect(harness.savedTabs == [.closed, .team, .mine])
    }

    @Test("A half changed under a repository list isn't a change of tab")
    func halfUnderListSavesNothing() {
        let harness = ReviewsHarness.twoRepos()
        let store = harness.makeStore()
        store.tab = .open

        store.filter = .mine

        #expect(store.tab == .open)
        #expect(harness.savedTabs == [.open])
    }

    @Test("Picking Open or Closed puts the inbox back on Team, so without a repository the section falls back to Team")
    func listsResetTheHalf() {
        let harness = ReviewsHarness.twoRepos()
        let store = harness.makeStore()

        store.tab = .mine
        store.tab = .closed
        #expect(store.filter == .team)
        #expect(store.tab == .closed)
        // The half moved under the list, not the tab: saved once.
        #expect(harness.savedTabs == [.mine, .closed])

        store.tab = .mine
        store.tab = .open
        #expect(store.filter == .team)
        #expect(harness.savedTabs == [.mine, .closed, .mine, .open])

        store.tab = .team
        #expect(store.filter == .team)
        #expect(store.repositoryList == nil)
    }

    // MARK: Leaving the repository's list

    @Test("Picking a row from outside, with a repository list on, goes back to the inbox")
    func revealLeavesRepositoryList() async {
        let (store, _) = await Self.loaded()
        store.tab = .open

        let found = store.reveal(Self.id(Self.app, 1))

        #expect(found)
        #expect(store.tab == .team)
        #expect(store.repositoryList == nil)
    }

    @Test("Picking the user's own row from a repository list lands on Mine, saved once")
    func revealMovesToTheHalf() async {
        let (store, harness) = await Self.loaded()
        store.tab = .closed

        store.reveal(Self.id(Self.api, 2))

        #expect(store.tab == .mine)
        #expect(harness.savedTabs == [.closed, .mine])
    }

    @Test("Picking a row that isn't there changes nothing")
    func revealOfNothing() async {
        let (store, harness) = await Self.loaded()
        store.tab = .open

        let found = store.reveal(Self.id(Self.app, 99))

        #expect(!found)
        #expect(store.tab == .open)
        #expect(harness.savedTabs == [.open])
    }

    @Test("Showing a repo leaves the repository list")
    func showRepoLeavesRepositoryList() async {
        let (store, _) = await Self.loaded()
        store.tab = .closed

        store.showRepo(Self.api)

        #expect(store.repositoryList == nil)
        #expect(store.repoFilter == Self.api)
    }

    @Test("Picking Open or Closed while the inbox is narrowed to a repo leaves the filter, and what it set aside")
    func listsLeaveTheRepoFilter() async {
        let (store, _) = await Self.loaded()
        store.showRepo(Self.api)
        #expect(store.repoFilter == Self.api)

        store.tab = .closed

        #expect(store.repoFilter == nil)
        #expect(store.tab == .closed)

        store.tab = .open
        store.showRepo(Self.api)
        store.tab = .closed
        store.showAllRepos()

        #expect(store.repoFilter == nil)
        #expect(store.tab == .closed)
    }

    @Test("Showing a repo that isn't followed changes nothing")
    func showUnknownRepo() async {
        let (store, _) = await Self.loaded()
        store.tab = .closed

        store.showRepo("gitlab.example.test/none/repo")

        #expect(store.tab == .closed)
        #expect(store.repoFilter == nil)
    }

    @Test("Closing the repo filter with nothing selected brings back the tab from before, Open and Closed too")
    func closingFilterRestoresTab() async {
        let (store, harness) = await Self.loaded()
        store.tab = .closed
        store.showRepo(Self.api)

        store.showAllRepos()

        #expect(store.repoFilter == nil)
        #expect(store.tab == .closed)
        #expect(harness.savedTabs.last == .closed)
    }

    @Test("Moving the filter to another repo keeps the tab from before the first one")
    func switchingRepoKeepsTheTabFromBefore() async {
        let (store, _) = await Self.loaded()
        store.tab = .open
        store.showRepo(Self.api)
        store.showRepo(Self.app)
        #expect(store.repositoryList == nil)

        store.showAllRepos()

        #expect(store.tab == .open)
    }

    @Test("Closing the repo filter with a row selected goes to the half that shows it")
    func closingFilterWithSelection() async {
        let (store, _) = await Self.loaded()
        store.tab = .closed
        store.showRepo(Self.api)
        store.selectedID = Self.id(Self.api, 2)

        store.showAllRepos()

        #expect(store.repoFilter == nil)
        #expect(store.tab == .mine)
        #expect(store.repositoryList == nil)
    }

    @Test("What was set aside by a filter that closed doesn't come back later")
    func setAsideIsPerFilter() async {
        let (store, _) = await Self.loaded()
        store.tab = .closed
        store.showRepo(Self.api)
        store.selectedID = Self.id(Self.api, 2)
        store.showAllRepos()
        #expect(store.tab == .mine)

        store.selectedID = nil
        store.tab = .open
        store.showAllRepos()

        #expect(store.tab == .open)
    }

    @Test("Showing every repo while no repo is shown leaves the tab alone")
    func showAllWithoutFilter() async {
        let (store, _) = await Self.loaded()
        store.tab = .open

        store.showAllRepos()

        #expect(store.tab == .open)
    }
}
