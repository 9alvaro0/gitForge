import Foundation
import Testing
@testable import gitForge

/// Pull requests opened from a link (R2 Rulings 8 to 11): the Others, the
/// account a link is read with, and what a refresh, the × and the snapshot
/// do to them.
@Suite("Reviews store, the Others")
@MainActor
struct ReviewsStoreOthersTests {
    private static let app = ReviewsHarness.key("team/app")
    private static let api = ReviewsHarness.key("team/api")
    private static let lib = ReviewsHarness.key("oss/lib")

    /// The row id of pull request `number` in the repo with key `repo`.
    private static func id(_ repo: String, _ number: Int) -> InboxPull.ID { "\(repo)#\(number)" }

    private static func link(_ path: String, _ number: Int) -> PullRequestLink {
        PullRequestLink(host: ReviewsHarness.host(path), number: number, instanceId: ReviewsHarness.instance.id)
    }

    private static func detailReads(_ harness: ReviewsHarness) -> Int { harness.provider.state { $0.detailReads } }

    /// team/app (a clone) and team/api (activity) read, each with a pull
    /// request of `octo`. oss/lib, which isn't followed, has !5 and !6 open
    /// and !7 merged on the host.
    private static func loaded() async -> (store: ReviewsStore, harness: ReviewsHarness) {
        let harness = ReviewsHarness.twoRepos()
        harness.provider.state {
            $0.lists["team/app"] = [ReviewsHarness.pr(1, by: "octo", updated: 100)]
            $0.lists["team/api"] = [ReviewsHarness.pr(2, by: "octo", updated: 200)]
            $0.lists["oss/lib"] = [ReviewsHarness.pr(5, by: "octo", updated: 300),
                                   ReviewsHarness.pr(6, by: "ana", updated: 250),
                                   ReviewsHarness.pr(7, by: "octo", state: .merged, updated: 50)]
        }
        let store = harness.makeStore()
        await store.refresh(force: true)
        return (store, harness)
    }

    /// `loaded()` with oss/lib !5 by `lucia` and !8 by `marta`, the user, open
    /// on the host and not yet among the Others.
    private static func withLuciaAndMarta() async -> (store: ReviewsStore, harness: ReviewsHarness) {
        let (store, harness) = await loaded()
        harness.provider.state {
            $0.lists["oss/lib"] = [ReviewsHarness.pr(5, by: "lucia", updated: 300),
                                   ReviewsHarness.pr(8, by: "marta", updated: 350)]
        }
        return (store, harness)
    }

    /// `loaded()` with team/app !9 by `author` on the host, opened from its
    /// link before a refresh lists it.
    private static func newPull(by author: String) async -> (store: ReviewsStore, harness: ReviewsHarness) {
        let (store, harness) = await loaded()
        harness.provider.state { $0.lists["team/app"]?.append(ReviewsHarness.pr(9, by: author, updated: 400)) }
        let outcome = await store.openLink(link("team/app", 9))
        #expect(outcome == .opened(id(app, 9)))
        return (store, harness)
    }

    // MARK: Opening a link

    @Test("A link to a row of the list selects that row, without reading anything")
    func linkToFollowedRow() async {
        let (store, harness) = await Self.loaded()
        let id = Self.id(Self.app, 1)

        let outcome = await store.openLink(Self.link("team/app", 1))

        #expect(outcome == .opened(id))
        #expect(store.selectedID == id)
        #expect(store.selectedItem?.id == id)
        #expect(store.others.isEmpty)
        #expect(store.openingLink == nil)
        #expect(Self.detailReads(harness) == 0)
    }

    @Test("A link to a repo that isn't followed opens in the Others, with a repo of its own and a detail store")
    func linkToUnfollowedRepo() async throws {
        let (store, harness) = await Self.loaded()
        let id = Self.id(Self.lib, 5)

        let outcome = await store.openLink(Self.link("oss/lib", 5))

        #expect(outcome == .opened(id))
        #expect(store.openingLink == nil)
        #expect(store.selectedID == id)
        #expect(store.visibleOthers.map(\.id) == [id])
        #expect(store.listContent == .groups(store.groups, others: store.visibleOthers))
        #expect(!store.repos.contains { $0.id == Self.lib })
        let item = try #require(store.selectedItem)
        #expect(item.id == id)
        #expect(item.pull.state == .open)
        #expect(item.repo.sources.isEmpty)
        #expect(item.repo.localURL == nil)
        #expect(item.repo.accountId == harness.account.id)
        #expect(item.repo.cloneURL == "https://gitlab.example.test/oss/lib.git")

        let detail = try #require(store.detailStore(for: Self.lib))
        await store.open(item)
        #expect(detail.selected?.number == 5)
    }

    @Test("A link to a merged pull request opens in the Others, merged")
    func closedLinkReadOnly() async {
        let (store, _) = await Self.loaded()
        let id = Self.id(Self.lib, 7)

        let outcome = await store.openLink(Self.link("oss/lib", 7))

        #expect(outcome == .opened(id))
        #expect(store.others.map(\.id) == [id])
        #expect(store.others.first?.pull.state == .merged)
        #expect(store.selectedItem?.pull.state == .merged)
    }

    @Test("A link to a row of a followed repo moves the inbox to the half that shows it and asks the list to show it")
    func followedLinkMovesHalf() async {
        let (store, harness) = await Self.loaded()
        harness.provider.state { $0.lists["team/api"]?.append(ReviewsHarness.pr(3, by: "marta", updated: 150)) }
        await store.refresh(force: true)

        // Someone else's, with Mine on.
        store.filter = .mine
        _ = await store.openLink(Self.link("team/app", 1))
        #expect(store.filter == .team)
        #expect(store.selectedItem?.id == Self.id(Self.app, 1))
        #expect(store.revealRequest?.id == Self.id(Self.app, 1))

        // The user's own, with Team on.
        _ = await store.openLink(Self.link("team/api", 3))
        #expect(store.filter == .mine)
        #expect(store.selectedItem?.id == Self.id(Self.api, 3))
        #expect(store.revealRequest?.id == Self.id(Self.api, 3))
    }

    @Test("A link that lands among the Others moves the inbox to the half of its author and asks the list to show it")
    func otherLinkSetsHalf() async {
        let (store, _) = await Self.withLuciaAndMarta()

        // Someone else's, with Mine on.
        store.filter = .mine
        _ = await store.openLink(Self.link("oss/lib", 5))
        #expect(store.filter == .team)
        #expect(store.selectedItem?.id == Self.id(Self.lib, 5))
        #expect(store.revealRequest?.id == Self.id(Self.lib, 5))

        // The user's own, with Team on.
        _ = await store.openLink(Self.link("oss/lib", 8))
        #expect(store.filter == .mine)
        #expect(store.selectedItem?.id == Self.id(Self.lib, 8))
        #expect(store.revealRequest?.id == Self.id(Self.lib, 8))
    }

    @Test("Revealing an Other moves the inbox to the half that shows it, as a row does")
    func revealOtherSetsHalf() async {
        let (store, _) = await Self.withLuciaAndMarta()
        _ = await store.openLink(Self.link("oss/lib", 5))
        _ = await store.openLink(Self.link("oss/lib", 8))
        store.filter = .team
        store.selectedID = nil

        #expect(store.reveal(Self.id(Self.lib, 8)))
        #expect(store.filter == .mine)
        #expect(store.selectedItem?.id == Self.id(Self.lib, 8))
        #expect(store.revealRequest?.id == Self.id(Self.lib, 8))
        #expect(store.repositoryList == nil)

        #expect(store.reveal(Self.id(Self.lib, 5)))
        #expect(store.filter == .team)
        #expect(store.selectedItem?.id == Self.id(Self.lib, 5))
    }

    @Test("The Others show under the half of their author: Team's are someone else's and Mine's are the user's")
    func othersByHalf() async {
        let (store, _) = await Self.withLuciaAndMarta()
        _ = await store.openLink(Self.link("oss/lib", 5))
        _ = await store.openLink(Self.link("oss/lib", 8))
        #expect(store.others.map(\.id) == [Self.id(Self.lib, 8), Self.id(Self.lib, 5)])

        store.filter = .team
        #expect(store.visibleOthers.map(\.id) == [Self.id(Self.lib, 5)])
        store.filter = .mine
        #expect(store.visibleOthers.map(\.id) == [Self.id(Self.lib, 8)])
        #expect(store.listContent == .groups(store.groups, others: store.visibleOthers))
    }

    @Test("With the user's login still unread none of the Others is theirs")
    func othersWithUnknownLogin() async {
        // Never refreshed: no account has told its login yet.
        let harness = ReviewsHarness()
        harness.provider.state { $0.lists["oss/lib"] = [ReviewsHarness.pr(8, by: "marta", updated: 350)] }
        let store = harness.makeStore()
        _ = await store.openLink(Self.link("oss/lib", 8))

        #expect(store.logins.isEmpty)
        #expect(store.filter == .team)
        #expect(store.visibleOthers.map(\.id) == [Self.id(Self.lib, 8)])
        store.filter = .mine
        #expect(store.visibleOthers.isEmpty)
    }

    @Test("A link to an Other already open moves to its half and asks the list to show it again")
    func reopenedLinkScrolls() async {
        let (store, _) = await Self.loaded()
        _ = await store.openLink(Self.link("oss/lib", 5))
        store.filter = .mine
        let request = store.revealRequest

        _ = await store.openLink(Self.link("oss/lib", 5))

        #expect(store.filter == .team)
        #expect(store.revealRequest?.id == Self.id(Self.lib, 5))
        #expect(store.revealRequest != request)
    }

    @Test("Picking an Other's row by hand keeps the half and asks for no scroll")
    func manualSelectionKeepsHalf() async {
        let (store, _) = await Self.loaded()
        _ = await store.openLink(Self.link("oss/lib", 5))
        _ = await store.openLink(Self.link("oss/lib", 6))
        let request = store.revealRequest
        // Both are someone else's: Team shows them.
        #expect(store.filter == .team)
        #expect(store.visibleOthers.map(\.id) == [Self.id(Self.lib, 6), Self.id(Self.lib, 5)])

        store.selectedID = Self.id(Self.lib, 5)

        #expect(store.filter == .team)
        #expect(store.selectedItem?.id == Self.id(Self.lib, 5))
        #expect(store.revealRequest == request)
    }

    @Test("A repo that isn't followed but has a clone the last refresh saw opens with that clone")
    func otherKnowsItsClone() async {
        let harness = ReviewsHarness()
        // A clone of oss/lib, outside the account's membership: not followed.
        harness.clonesAreMembers = false
        harness.locals = [ReviewsHarness.local("oss/lib")]
        harness.browser.state { $0.members = [ReviewsHarness.member("2", "team/api")] }
        harness.provider.state { $0.lists["oss/lib"] = [ReviewsHarness.pr(5, by: "octo", updated: 300)] }
        let store = harness.makeStore()
        await store.refresh(force: true)
        #expect(store.repos.isEmpty)

        _ = await store.openLink(Self.link("oss/lib", 5))

        #expect(store.others.first?.repo.localURL == URL(fileURLWithPath: "/r/oss/lib"))
        #expect(store.others.first?.repo.sources.isEmpty == true)
    }

    @Test("Opening a link again moves its row to the top, without reading it again")
    func reopenedLinkMovesUp() async {
        let (store, harness) = await Self.loaded()
        _ = await store.openLink(Self.link("oss/lib", 5))
        _ = await store.openLink(Self.link("oss/lib", 6))
        #expect(store.others.map(\.id) == [Self.id(Self.lib, 6), Self.id(Self.lib, 5)])
        let reads = Self.detailReads(harness)

        let outcome = await store.openLink(Self.link("oss/lib", 5))

        #expect(outcome == .opened(Self.id(Self.lib, 5)))
        #expect(store.others.map(\.id) == [Self.id(Self.lib, 5), Self.id(Self.lib, 6)])
        #expect(store.selectedID == Self.id(Self.lib, 5))
        #expect(Self.detailReads(harness) == reads)
    }

    @Test("A later link wins: an earlier one that lands after it adds its row but doesn't select it")
    func laterLinkWins() async {
        let (store, harness) = await Self.loaded()
        let gate = AsyncGate()
        harness.provider.state { $0.detailGates[5] = gate }
        store.selectedID = Self.id(Self.app, 1)

        let first = Task { await store.openLink(Self.link("oss/lib", 5)) }
        await gate.waiting()
        #expect(store.openingLink == PendingLink(host: ReviewsHarness.host("oss/lib"), number: 5))
        #expect(store.selectedID == nil)

        let second = await store.openLink(Self.link("oss/lib", 6))
        #expect(second == .opened(Self.id(Self.lib, 6)))
        #expect(store.selectedID == Self.id(Self.lib, 6))
        #expect(store.openingLink == nil)

        gate.open()
        #expect(await first.value == .opened(Self.id(Self.lib, 5)))
        #expect(store.selectedID == Self.id(Self.lib, 6))
        #expect(store.openingLink == nil)
        // By opening order: the later link's row stays on top.
        #expect(store.others.map(\.id) == [Self.id(Self.lib, 6), Self.id(Self.lib, 5)])
    }

    // MARK: The account

    @Test("A link the preferred account can't see opens with the next account of the instance that can")
    func accountFallback() async {
        let harness = ReviewsHarness()
        let ana = HostingAccount(instanceId: ReviewsHarness.instance.id, login: "ana", method: .oauth, status: .ok)
        harness.accounts.append(ana)
        harness.tokenFor = [harness.account.id: .token("t-marta"), ana.id: .token("t-ana")]
        harness.provider.state {
            $0.lists["oss/lib"] = [ReviewsHarness.pr(5, by: "octo", updated: 300)]
            $0.detailFailures["t-marta"] = .notFound
        }
        let store = harness.makeStore()

        let outcome = await store.openLink(Self.link("oss/lib", 5))

        #expect(outcome == .opened(Self.id(Self.lib, 5)))
        #expect(store.others.first?.repo.accountId == ana.id)
        #expect(Self.detailReads(harness) == 2)
    }

    @Test("The Others of a repo share its repo: a read with another account takes them over, without the old store")
    func othersShareTheirRepo() async {
        let harness = ReviewsHarness()
        let ana = HostingAccount(instanceId: ReviewsHarness.instance.id, login: "ana", method: .oauth, status: .ok)
        harness.accounts.append(ana)
        harness.tokenFor = [harness.account.id: .token("t-marta"), ana.id: .token("t-ana")]
        harness.provider.state {
            $0.lists["oss/lib"] = [ReviewsHarness.pr(5, by: "octo", updated: 300),
                                   ReviewsHarness.pr(6, by: "ana", updated: 250)]
        }
        let store = harness.makeStore()
        _ = await store.openLink(Self.link("oss/lib", 5))
        let detail = store.detailStore(for: Self.lib)
        #expect(detail != nil)
        #expect(store.others.map(\.repo.accountId) == [harness.account.id])

        // marta can't see oss/lib any more: ana reads !6.
        harness.provider.state { $0.detailFailures["t-marta"] = .notFound }
        _ = await store.openLink(Self.link("oss/lib", 6))

        #expect(store.others.map(\.repo.accountId) == [ana.id, ana.id])
        #expect(store.detailStore(for: Self.lib) !== detail)
    }

    @Test("A link on an instance without accounts asks to connect one, without a request")
    func noAccountOnInstance() async throws {
        let (store, harness) = await Self.loaded()
        let elsewhere = HostingInstance(kind: .gitlab, host: "code.example.test")
        let reads = harness.provider.state { $0.reads.count }
        let link = PullRequestLink(host: try #require(RemoteHost.make(fullName: "oss/lib", on: elsewhere)), number: 5,
                                   instanceId: elsewhere.id)

        let outcome = await store.openLink(link)

        #expect(outcome == .connectAccount(instanceId: elsewhere.id))
        #expect(Self.detailReads(harness) == 0)
        #expect(harness.provider.state { $0.reads.count } == reads)
        #expect(store.others.isEmpty)
        #expect(store.openingLink == nil)
    }

    @Test("A link no account can see fails, naming the repo and the number, and gives back the selection it cleared")
    func unreadableLink() async {
        let (store, harness) = await Self.loaded()
        harness.provider.state { $0.detailFailures["t"] = .notFound }
        let selected = Self.id(Self.app, 1)
        store.selectedID = selected

        let outcome = await store.openLink(Self.link("oss/lib", 5))

        guard case .failed(let message) = outcome else {
            Issue.record("Expected a failure, got \(outcome)")
            return
        }
        #expect(message.contains("oss/lib"))
        #expect(message.contains("!5"))
        #expect(message.hasSuffix(PullRequestStore.message(for: PullRequestFetchError.notFound)))
        #expect(store.others.isEmpty)
        #expect(store.selectedID == selected)
        #expect(store.selectedItem?.id == selected)
        #expect(store.openingLink == nil)
    }

    @Test("A link that asks to connect an account gives back the selection it cleared")
    func connectLinkGivesBackSelection() async throws {
        let (store, _) = await Self.loaded()
        let selected = Self.id(Self.api, 2)
        store.selectedID = selected
        let elsewhere = HostingInstance(kind: .gitlab, host: "code.example.test")
        let link = PullRequestLink(host: try #require(RemoteHost.make(fullName: "oss/lib", on: elsewhere)), number: 5,
                                   instanceId: elsewhere.id)

        let outcome = await store.openLink(link)

        #expect(outcome == .connectAccount(instanceId: elsewhere.id))
        #expect(store.selectedID == selected)
        #expect(store.selectedItem?.id == selected)
    }

    @Test("A failed link leaves nothing selected when the row it cleared left the list while it was read")
    func failedLinkRowLeft() async {
        let (store, harness) = await Self.loaded()
        let gate = AsyncGate()
        harness.provider.state {
            $0.detailGates[5] = gate
            $0.detailFailures["t"] = .notFound
        }
        store.selectedID = Self.id(Self.app, 1)

        let opening = Task { await store.openLink(Self.link("oss/lib", 5)) }
        await gate.waiting()
        // team/app's !1 was merged elsewhere: the refresh no longer lists it.
        harness.provider.state { $0.lists["team/app"] = [] }
        await store.refresh(force: true)
        gate.open()

        guard case .failed = await opening.value else {
            Issue.record("Expected a failure")
            return
        }
        #expect(store.selectedID == nil)
        #expect(store.selectedItem == nil)
    }

    @Test("A failed link doesn't take back a row picked while it was read")
    func failedLinkKeepsNewPick() async {
        let (store, harness) = await Self.loaded()
        let gate = AsyncGate()
        harness.provider.state {
            $0.detailGates[5] = gate
            $0.detailFailures["t"] = .notFound
        }
        store.selectedID = Self.id(Self.app, 1)

        let opening = Task { await store.openLink(Self.link("oss/lib", 5)) }
        await gate.waiting()
        let picked = Self.id(Self.api, 2)
        store.selectedID = picked
        gate.open()

        guard case .failed = await opening.value else {
            Issue.record("Expected a failure")
            return
        }
        #expect(store.selectedID == picked)
    }

    @Test("A rejected token is renewed once and the link read again")
    func linkRenewsRejectedToken() async {
        let (store, harness) = await Self.loaded()
        harness.answer = { rejected in .token(rejected == nil ? "t" : "t2") }
        harness.provider.state { $0.detailFailures["t"] = .unauthorized }

        let outcome = await store.openLink(Self.link("oss/lib", 5))

        #expect(outcome == .opened(Self.id(Self.lib, 5)))
        #expect(harness.renewals == ["t"])
    }

    @Test("An error other than not found or forbidden stops at the first account and says why")
    func linkStopsOnOtherErrors() async {
        let harness = ReviewsHarness()
        let ana = HostingAccount(instanceId: ReviewsHarness.instance.id, login: "ana", method: .oauth, status: .ok)
        harness.accounts.append(ana)
        harness.tokenFor = [harness.account.id: .token("t-marta"), ana.id: .token("t-ana")]
        let offline = PullRequestFetchError.network("offline")
        harness.provider.state {
            $0.lists["oss/lib"] = [ReviewsHarness.pr(5, by: "octo", updated: 300)]
            $0.detailFailures["t-marta"] = offline
        }
        let store = harness.makeStore()

        let outcome = await store.openLink(Self.link("oss/lib", 5))

        #expect(outcome == .failed(PullRequestStore.message(for: offline)))
        #expect(Self.detailReads(harness) == 1)
        #expect(store.others.isEmpty)
    }

    @Test("When no account sees the link and one must be connected again, connecting comes first")
    func linkAsksToReconnect() async {
        let harness = ReviewsHarness()
        let dead = HostingAccount(instanceId: ReviewsHarness.instance.id, login: "octo", method: .oauth,
                                  status: .needsAttention(.revoked))
        harness.accounts.append(dead)
        harness.provider.state { $0.detailFailures["t"] = .notFound }
        let store = harness.makeStore()

        let outcome = await store.openLink(Self.link("oss/lib", 5))

        #expect(outcome == .connectAccount(instanceId: ReviewsHarness.instance.id))
        #expect(Self.detailReads(harness) == 1)
    }

    // MARK: Refresh, list and snapshot

    @Test("A refresh keeps the selected Other, its row and its detail store")
    func othersSurviveRefresh() async {
        let (store, _) = await Self.loaded()
        let id = Self.id(Self.lib, 5)
        _ = await store.openLink(Self.link("oss/lib", 5))
        let detail = store.detailStore(for: Self.lib)
        #expect(detail != nil)

        await store.refresh(force: true)

        #expect(store.selectedID == id)
        #expect(store.selectedItem?.id == id)
        #expect(store.others.map(\.id) == [id])
        #expect(store.detailStore(for: Self.lib) === detail)
    }

    @Test("An Other whose repo comes to be followed with the account that read it keeps its detail store")
    func otherFollowedWithSameAccount() async throws {
        let harness = ReviewsHarness()
        harness.browser.state { $0.members = [ReviewsHarness.member("3", "oss/lib")] }
        harness.provider.state { $0.lists["oss/lib"] = [ReviewsHarness.pr(5, by: "octo", updated: 300)] }
        let store = harness.makeStore()
        await store.refresh(force: true)
        #expect(store.repos.isEmpty)
        let id = Self.id(Self.lib, 5)
        _ = await store.openLink(Self.link("oss/lib", 5))
        let detail = try #require(store.detailStore(for: Self.lib))

        // The user's activity there: oss/lib is followed, with the same account.
        harness.activity.state { $0.hits = [ActivityHit(ref: .projectId("3"), at: ReviewsHarness.date(1_789_000_000))] }
        await store.refresh(force: true)

        #expect(store.repos.map(\.id) == [Self.lib])
        #expect(store.others.first?.repo == store.repos.first)
        #expect(store.selectedID == id)
        #expect(store.selectedItem?.repo.accountId == harness.account.id)
        #expect(store.selectedItem?.repo.sources.isEmpty == false)
        #expect(store.detailStore(for: Self.lib) === detail)
    }

    @Test("An Other whose repo comes to be followed with another account takes that account and a new detail store")
    func otherFollowedWithAnotherAccount() async throws {
        let harness = ReviewsHarness()
        let ana = HostingAccount(instanceId: ReviewsHarness.instance.id, login: "ana", method: .oauth, status: .ok)
        harness.accounts.append(ana)
        harness.tokenFor = [harness.account.id: .token("t-marta"), ana.id: .token("t-ana")]
        // Only ana belongs to oss/lib.
        harness.browser.state { $0.membersByToken["t-ana"] = [ReviewsHarness.member("3", "oss/lib")] }
        harness.provider.state { $0.lists["oss/lib"] = [ReviewsHarness.pr(5, by: "octo", updated: 300)] }
        let store = harness.makeStore()
        await store.refresh(force: true)
        #expect(store.repos.isEmpty)
        let id = Self.id(Self.lib, 5)
        // marta, first in store order, reads the link.
        _ = await store.openLink(Self.link("oss/lib", 5))
        #expect(store.others.first?.repo.accountId == harness.account.id)
        let detail = try #require(store.detailStore(for: Self.lib))

        // ana's activity there: oss/lib is followed, read with ana.
        harness.activity.state { $0.hits = [ActivityHit(ref: .projectId("3"), at: ReviewsHarness.date(1_789_000_000))] }
        await store.refresh(force: true)

        #expect(store.repos.map(\.accountId) == [ana.id])
        #expect(store.others.first?.repo.accountId == ana.id)
        #expect(store.selectedID == id)
        #expect(store.selectedItem?.repo.accountId == ana.id)
        let replaced = try #require(store.detailStore(for: Self.lib))
        #expect(replaced !== detail)
    }

    @Test("An Other of a repo that stops being followed stays, loose, with the clone the refresh saw and its detail store")
    func otherOfRepoNoLongerFollowed() async throws {
        let (store, harness) = await Self.newPull(by: "octo")
        let id = Self.id(Self.app, 9)
        #expect(store.others.first?.repo.sources.isEmpty == false)
        let detail = try #require(store.detailStore(for: Self.app))

        // The account no longer belongs to team/app, once its membership is read
        // again: the clone isn't followed any more.
        harness.clonesAreMembers = false
        harness.now = harness.now.addingTimeInterval(ReviewsStore.membershipTTL + 1)
        await store.refresh(force: true)

        #expect(!store.repos.contains { $0.id == Self.app })
        let other = try #require(store.others.first)
        #expect(other.id == id)
        #expect(other.repo.sources.isEmpty)
        #expect(other.repo.lastActivity == nil)
        #expect(other.repo.localURL == URL(fileURLWithPath: "/r/team/app"))
        #expect(other.repo.accountId == harness.account.id)
        #expect(store.selectedID == id)
        #expect(store.selectedItem?.id == id)
        #expect(store.detailStore(for: Self.app) === detail)
    }

    @Test("Someone else's new pull request of a followed repo is an Other until a refresh lists it in Team")
    func newPullOfFollowedRepo() async {
        let (store, _) = await Self.newPull(by: "octo")
        let id = Self.id(Self.app, 9)
        #expect(store.others.map(\.id) == [id])
        #expect(store.others.first?.repo == store.repos.first { $0.id == Self.app })
        #expect(store.visibleOthers.map(\.id) == [id])
        #expect(store.selectedItem?.id == id)

        await store.refresh(force: true)

        #expect(store.filter == .team)
        #expect(store.visibleOthers.isEmpty)
        #expect(store.groups.first { $0.repo.id == Self.app }?.pulls.contains { $0.id == id } == true)
        #expect(store.selectedItem?.id == id)
    }

    @Test("The selected Other stays among the Others while the current half hides its row, which a refresh listed")
    func selectedOtherStaysVisible() async {
        let (store, _) = await Self.newPull(by: "marta")
        let id = Self.id(Self.app, 9)
        #expect(store.filter == .mine)

        await store.refresh(force: true)

        // Listed in Mine now.
        #expect(store.visibleOthers.isEmpty)
        #expect(store.groups.first { $0.repo.id == Self.app }?.pulls.map(\.id) == [id])

        // Team hides its row: the selection stays among the Others.
        store.filter = .team
        #expect(store.visibleOthers.map(\.id) == [id])
        #expect(store.selectedItem?.id == id)

        store.selectedID = nil
        #expect(store.visibleOthers.isEmpty)
    }

    @Test("The × removes the row and its selection, and the detail store once no row uses its repo")
    func closeOther() async {
        let (store, _) = await Self.loaded()
        _ = await store.openLink(Self.link("oss/lib", 6))
        _ = await store.openLink(Self.link("oss/lib", 5))
        let detail = store.detailStore(for: Self.lib)
        #expect(detail != nil)

        store.closeOther(Self.id(Self.lib, 6))
        #expect(store.others.map(\.id) == [Self.id(Self.lib, 5)])
        #expect(store.selectedID == Self.id(Self.lib, 5))
        #expect(store.detailStore(for: Self.lib) === detail)

        store.closeOther(Self.id(Self.lib, 5))
        #expect(store.others.isEmpty)
        #expect(store.selectedID == nil)
        #expect(store.detailStore(for: Self.lib) == nil)
    }

    @Test("The Others aren't saved: a new store on the same folder starts without them")
    func othersNotInSnapshot() async {
        let (store, harness) = await Self.loaded()
        _ = await store.openLink(Self.link("oss/lib", 5))
        await store.refresh(force: true)
        #expect(store.others.map(\.id) == [Self.id(Self.lib, 5)])

        let relaunched = harness.makeStore()
        relaunched.loadSnapshot()

        #expect(!relaunched.repos.isEmpty)
        #expect(relaunched.others.isEmpty)
        #expect(relaunched.pulls[Self.lib] == nil)
    }

    @Test("Without accounts the Others go")
    func othersClearedWithoutAccounts() async {
        let (store, harness) = await Self.loaded()
        _ = await store.openLink(Self.link("oss/lib", 5))
        #expect(store.others.map(\.id) == [Self.id(Self.lib, 5)])

        harness.accounts = []
        await store.refresh(force: true)

        #expect(store.others.isEmpty)
        #expect(store.selectedID == nil)
        #expect(store.detailStore(for: Self.lib) == nil)
    }

    @Test("A merge seen in the detail updates the Other's row")
    func noteDetail() async {
        let (store, _) = await Self.loaded()
        let id = Self.id(Self.lib, 5)
        _ = await store.openLink(Self.link("oss/lib", 5))

        store.noteDetail(ReviewsHarness.pr(5, by: "octo", state: .merged, updated: 300), for: id)

        #expect(store.others.first?.pull.state == .merged)
        #expect(store.selectedItem?.pull.state == .merged)
    }

    @Test("Narrowed to a repo, the Others don't show; revealing one shows every repo again")
    func repoFilterHidesOthers() async {
        let (store, _) = await Self.loaded()
        let id = Self.id(Self.lib, 5)
        _ = await store.openLink(Self.link("oss/lib", 5))

        store.showRepo(Self.app)
        #expect(store.visibleOthers.isEmpty)
        #expect(store.others.map(\.id) == [id])

        #expect(store.reveal(id))
        #expect(store.repoFilter == nil)
        #expect(store.selectedItem?.id == id)
        #expect(store.visibleOthers.map(\.id) == [id])
    }

    @Test("The palette searches the Others too, each once")
    func searchableIncludesOthers() async {
        let (store, _) = await Self.newPull(by: "octo")
        _ = await store.openLink(Self.link("oss/lib", 5))
        await store.refresh(force: true)

        let ids = store.searchablePulls.map(\.id)
        #expect(ids.count(where: { $0 == Self.id(Self.lib, 5) }) == 1)
        #expect(ids.count(where: { $0 == Self.id(Self.app, 9) }) == 1)
        #expect(ids.count == Set(ids).count)
    }
}
