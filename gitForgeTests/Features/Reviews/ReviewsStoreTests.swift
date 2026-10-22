import Foundation
import Testing
@testable import gitForge

@Suite("Reviews store")
@MainActor
struct ReviewsStoreTests {
    private static func reads(_ harness: ReviewsHarness) -> Int { harness.provider.state { $0.reads.count } }

    @Test("Groups follow their newest update, and Team and Mine split the pull requests by author")
    func groupsAndFilters() async {
        let harness = ReviewsHarness.twoRepos()
        harness.provider.state {
            $0.lists["team/app"] = [ReviewsHarness.pr(1, by: "octo", updated: 100),
                                    ReviewsHarness.pr(2, by: "marta", updated: 300)]
            $0.lists["team/api"] = [ReviewsHarness.pr(3, by: "octo", updated: 200),
                                    ReviewsHarness.pr(4, by: "octo", state: .draft, updated: 150),
                                    ReviewsHarness.pr(5, by: "marta", state: .draft, updated: 50)]
        }
        let store = harness.makeStore()
        await store.refresh(force: true)

        #expect(store.repos.first { $0.host.repo == "app" }?.sources == [.local])
        #expect(store.repos.first { $0.host.repo == "api" }?.sources == [.activity])
        #expect(store.filter == .team)
        #expect(store.groups.map(\.repo.host.repo) == ["api", "app"])
        #expect(store.groups.map { $0.pulls.map(\.pull.number) } == [[3, 4], [1]])
        #expect(store.groups.first?.pulls.first?.id == "gitlab.example.test/team/api#3")
        #expect(store.groups.allSatisfy { $0.error == nil })

        store.filter = .mine
        #expect(store.groups.map(\.repo.host.repo) == ["app", "api"])
        #expect(store.groups.map { $0.pulls.map(\.pull.number) } == [[2], [5]])
    }

    @Test("The count is the open pull requests of others: no drafts, and the login matches in any case")
    func badge() async {
        let harness = ReviewsHarness(login: "Marta")
        harness.locals = [ReviewsHarness.local("team/app")]
        harness.provider.state {
            $0.lists["team/app"] = [ReviewsHarness.pr(1, by: "octo", updated: 1),
                                    ReviewsHarness.pr(2, by: "lucia", updated: 2),
                                    ReviewsHarness.pr(3, by: "octo", updated: 3),
                                    ReviewsHarness.pr(4, by: "octo", state: .draft, updated: 4),
                                    ReviewsHarness.pr(5, by: "marta", updated: 5)]
        }
        let store = harness.makeStore()
        await store.refresh(force: true)

        #expect(store.badgeCount == 3)
        store.filter = .mine
        #expect(store.groups.map { $0.pulls.map(\.pull.number) } == [[5]])
    }

    @Test("A repo that answers 404 loses its pull requests and shows why, last; the other loads")
    func partialErrors() async {
        let harness = ReviewsHarness.twoRepos()
        harness.provider.state {
            $0.lists["team/app"] = [ReviewsHarness.pr(1, by: "octo", updated: 100)]
            $0.lists["team/api"] = [ReviewsHarness.pr(2, by: "octo", updated: 200)]
        }
        let store = harness.makeStore()
        await store.refresh(force: true)
        #expect(store.badgeCount == 2)

        harness.provider.state { $0.failures["team/api"] = .notFound }
        await store.refresh(force: true)

        let api = ReviewsHarness.key("team/api")
        #expect(store.pulls[api] == nil)
        #expect(store.repoErrors[api] == PullRequestStore.message(for: PullRequestFetchError.notFound))
        #expect(store.pulls[ReviewsHarness.key("team/app")]?.map(\.number) == [1])
        #expect(store.groups.map(\.repo.host.repo) == ["app", "api"])
        #expect(store.groups.last?.pulls.isEmpty == true)
        #expect(store.groups.last?.error == store.repoErrors[api])
        #expect(store.badgeCount == 1)
        #expect(!store.lastRefreshFailed)
    }

    @Test("A server that's down or busy keeps the repo's pull requests, without an error", arguments: [500, 502, 503, 429])
    func transientServerError(code: Int) async {
        let harness = ReviewsHarness()
        harness.locals = [ReviewsHarness.local("team/app")]
        harness.provider.state { $0.lists["team/app"] = [ReviewsHarness.pr(1, by: "octo", updated: 100)] }
        let store = harness.makeStore()
        await store.refresh(force: true)

        harness.provider.state { $0.failures["team/app"] = .server(code, "Service Unavailable") }
        await store.refresh(force: true)

        #expect(store.pulls[ReviewsHarness.key("team/app")]?.map(\.number) == [1])
        #expect(store.repoErrors.isEmpty)
        #expect(store.badgeCount == 1)
    }

    @Test("Any other server error still drops the repo's pull requests and says why")
    func otherServerError() async {
        let harness = ReviewsHarness()
        harness.locals = [ReviewsHarness.local("team/app")]
        harness.provider.state { $0.lists["team/app"] = [ReviewsHarness.pr(1, by: "octo", updated: 100)] }
        let store = harness.makeStore()
        await store.refresh(force: true)

        let error = PullRequestFetchError.server(422, "Unprocessable")
        harness.provider.state { $0.failures["team/app"] = error }
        await store.refresh(force: true)

        #expect(store.pulls[ReviewsHarness.key("team/app")] == nil)
        #expect(store.repoErrors[ReviewsHarness.key("team/app")] == PullRequestStore.message(for: error))
    }

    @Test("Offline, a refresh keeps the snapshot's pull requests and its date, and says it failed")
    func offlineKeepsSnapshot() async {
        let harness = ReviewsHarness.twoRepos()
        harness.provider.state {
            $0.lists["team/app"] = [ReviewsHarness.pr(1, by: "octo", updated: 100)]
            $0.lists["team/api"] = [ReviewsHarness.pr(2, by: "octo", updated: 200)]
        }
        await harness.makeStore().refresh(force: true)
        let savedAt = harness.now

        // The next launch, a day later (the membership is due again) and offline.
        harness.now = savedAt.addingTimeInterval(25 * 3600)
        let offline = PullRequestFetchError.network("The Internet connection appears to be offline.")
        harness.browser.state { $0.failure = offline }
        harness.activity.state { $0.failure = offline }
        harness.provider.state { $0.failEverything = offline }
        let store = harness.makeStore()
        store.loadSnapshot()
        #expect(store.lastRefreshedAt == savedAt)
        await store.refresh(force: true)

        #expect(store.groups.flatMap(\.pulls).map(\.pull.number).sorted() == [1, 2])
        #expect(store.lastRefreshFailed)
        #expect(store.lastRefreshedAt == savedAt)
        #expect(store.repoErrors.isEmpty)
        let onDisk = ReviewsSnapshotStore(directory: harness.directory).load()
        #expect(onDisk?.pulls.values.flatMap { $0 }.count == 2)
        #expect(onDisk?.savedAt == savedAt)
    }

    @Test("A rejected token is renewed once and the reads retried; an account to reconnect keeps its pull requests")
    func expiredToken() async {
        let harness = ReviewsHarness.twoRepos()
        harness.provider.state {
            $0.lists["team/app"] = [ReviewsHarness.pr(1, by: "octo", updated: 100)]
            $0.lists["team/api"] = [ReviewsHarness.pr(2, by: "octo", updated: 200)]
            $0.rejecting = ["old"]
        }
        harness.answer = { rejected in .token(rejected == nil ? "old" : "new") }
        let store = harness.makeStore()
        await store.refresh(force: true)

        #expect(harness.renewals == ["old"])
        #expect(store.badgeCount == 2)
        #expect(store.accountsNeedingAttention.isEmpty)

        // This time the renewal fails: the account has to be connected again.
        let accountId = harness.account.id
        harness.provider.state { $0.rejecting = ["stale"] }
        harness.answer = { rejected in
            rejected == nil
                ? .token("stale")
                : .connectAccount(instanceId: ReviewsHarness.instance.id, replacing: accountId)
        }
        await store.refresh(force: true)

        #expect(harness.renewals == ["old", "stale"])
        #expect(store.accountsNeedingAttention == [accountId])
        #expect(store.badgeCount == 2)
        #expect(store.repoErrors.isEmpty)

        // Connected again.
        harness.provider.state { $0.rejecting = [] }
        harness.answer = { _ in .token("fresh") }
        await store.refresh(force: true)
        #expect(store.accountsNeedingAttention.isEmpty)
    }

    @Test("The membership is read once a day")
    func membershipCached() async {
        let harness = ReviewsHarness.twoRepos()
        let store = harness.makeStore()
        await store.refresh(force: true)
        await store.refresh(force: true)
        #expect(harness.browser.state { $0.listings } == 1)
        #expect(store.repos.count == 2)

        harness.now = harness.now.addingTimeInterval(25 * 3600)
        await store.refresh(force: true)
        #expect(harness.browser.state { $0.listings } == 2)
        #expect(store.repos.count == 2)
    }

    @Test("Two refreshes in a row read the pull requests once, unless forced")
    func throttle() async {
        let harness = ReviewsHarness()
        harness.locals = [ReviewsHarness.local("team/app")]
        let store = harness.makeStore()
        await store.refresh()
        await store.refresh()
        #expect(Self.reads(harness) == 1)

        await store.refresh(force: true)
        #expect(Self.reads(harness) == 2)

        harness.now = harness.now.addingTimeInterval(ReviewsStore.reloadThrottle)
        await store.refresh()
        #expect(Self.reads(harness) == 3)
    }

    @Test("While a read runs and no repo is followed yet, the list shows the loading placeholder")
    func loadingBeforeAnyRepo() async {
        let harness = ReviewsHarness()
        harness.locals = [ReviewsHarness.local("team/app")]
        let store = harness.makeStore()
        let reading = AsyncGate()
        harness.localsGate = reading
        let round = Task { await store.refresh(force: true) }
        await reading.waiting()
        #expect(store.repos.isEmpty)
        #expect(store.listContent == .loading)

        reading.open()
        await round.value
        #expect(store.listContent == .empty)
    }

    @Test("A repo followed for the first time keeps the placeholder up until its pull requests land")
    func loadingForANewRepo() async {
        let harness = ReviewsHarness.twoRepos()
        // No activity in team/api yet: only the clone is followed, and it has nothing open.
        harness.activity.state { $0.hits = [] }
        let store = harness.makeStore()
        await store.refresh(force: true)
        #expect(store.repos.map(\.host.repo) == ["app"])
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
        #expect(store.repos.map(\.host.repo).sorted() == ["api", "app"])
        #expect(store.pulls[ReviewsHarness.key("team/app")]?.isEmpty == true)
        #expect(store.pulls[ReviewsHarness.key("team/api")] == nil)
        #expect(store.listContent == .loading)

        reading.open()
        await round.value
        #expect(store.listContent == .groups(store.groups))
        #expect(store.groups.count == 1)
    }

    @Test("With rows to show, a read doesn't hide them")
    func rowsStayWhileRefreshing() async {
        let harness = ReviewsHarness()
        harness.locals = [ReviewsHarness.local("team/app")]
        harness.provider.state { $0.lists["team/app"] = [ReviewsHarness.pr(1, by: "octo", updated: 1)] }
        let store = harness.makeStore()
        await store.refresh(force: true)
        #expect(store.groups.count == 1)

        let again = AsyncGate()
        harness.localsGate = again
        let next = Task { await store.refresh(force: true) }
        await again.waiting()
        #expect(store.listContent == .groups(store.groups))
        again.open()
        await next.value
    }

    @Test("A refresh over a filter known to be empty doesn't swap the empty state for the placeholder")
    func noFlashOverAKnownEmptyList() async {
        let harness = ReviewsHarness()
        harness.locals = [ReviewsHarness.local("team/app")]
        harness.provider.state { $0.lists["team/app"] = [ReviewsHarness.pr(1, by: "octo", updated: 1)] }
        let store = harness.makeStore()
        // Nothing of the user's: Mine is empty once every repo has been read.
        store.filter = .mine
        await store.refresh(force: true)
        #expect(store.pulls[ReviewsHarness.key("team/app")]?.count == 1)
        #expect(store.listContent == .empty)

        // The next round, held at the clones and then at the read of the repo.
        let listing = AsyncGate()
        let reading = AsyncGate()
        harness.localsGate = listing
        harness.provider.state { $0.gates["team/app"] = reading }
        let round = Task { await store.refresh(force: true) }
        await listing.waiting()
        #expect(store.isRefreshing)
        #expect(store.listContent == .empty)

        listing.open()
        await reading.waiting()
        #expect(store.isRefreshing)
        #expect(store.listContent == .empty)

        reading.open()
        await round.value
        #expect(!store.isRefreshing)
        #expect(store.listContent == .empty)
    }

    @Test("A repo of an account that needs attention is never read, so it doesn't keep the placeholder up")
    func withheldRepoDoesNotKeepThePlaceholder() async {
        let harness = ReviewsHarness.twoRepos()
        let dead = HostingAccount(instanceId: ReviewsHarness.instance.id, login: "octo", method: .oauth,
                                  status: .needsAttention(.revoked))
        harness.accounts.append(dead)
        // team/app is read with the dead account, team/api with the working one.
        harness.locals = [ReviewsHarness.local("team/app", account: dead.id)]
        let store = harness.makeStore()
        await store.refresh(force: true)
        #expect(store.accountsNeedingAttention == [dead.id])
        #expect(store.pulls[ReviewsHarness.key("team/api")]?.isEmpty == true)
        #expect(store.pulls[ReviewsHarness.key("team/app")] == nil)
        #expect(store.repoErrors.isEmpty)
        #expect(store.listContent == .empty)

        let listing = AsyncGate()
        harness.localsGate = listing
        let round = Task { await store.refresh(force: true) }
        await listing.waiting()
        #expect(store.listContent == .empty)

        listing.open()
        await round.value
        #expect(store.listContent == .empty)
    }

    @Test("Once a refresh that found no repo to follow ends, the list shows the empty state, not the placeholder")
    func emptyStateOnceARefreshWithNoReposEnds() async {
        // A connected account with no clones and no recent activity.
        let harness = ReviewsHarness()
        let store = harness.makeStore()

        await store.refresh(force: true)

        #expect(!store.isRefreshing)
        #expect(store.repos.isEmpty)
        #expect(store.listContent == .empty)
    }

    @Test("Without accounts a refresh reads no clones and writes nothing, and doesn't hold back the first with one")
    func noAccounts() async {
        let harness = ReviewsHarness()
        let account = harness.account
        harness.accounts = []
        harness.locals = [ReviewsHarness.local("team/app")]
        harness.provider.state { $0.lists["team/app"] = [ReviewsHarness.pr(1, by: "octo", updated: 1)] }
        let store = harness.makeStore()
        await store.refresh(force: true)
        await store.refresh(force: true)

        #expect(harness.localReads == 0)
        #expect(Self.reads(harness) == 0)
        #expect(ReviewsSnapshotStore(directory: harness.directory).load() == nil)
        #expect(store.repos.isEmpty)

        // An account is connected right after: the next refresh reads, throttle or not.
        harness.accounts = [account]
        await store.refresh()
        #expect(harness.localReads == 1)
        #expect(store.badgeCount == 1)
    }

    @Test("When the last account goes, a refresh empties the inbox and saves it once")
    func lastAccountRemoved() async throws {
        let harness = ReviewsHarness.twoRepos()
        harness.provider.state {
            $0.lists["team/app"] = [ReviewsHarness.pr(1, by: "octo", updated: 100)]
            $0.lists["team/api"] = [ReviewsHarness.pr(2, by: "octo", updated: 200)]
        }
        let store = harness.makeStore()
        await store.refresh(force: true)
        let item = try #require(store.groups.first?.pulls.first)
        store.selectedID = item.id
        #expect(store.detailStore(for: item.repo.id) != nil)
        let localReads = harness.localReads

        harness.accounts = []
        await store.refresh(force: true)

        #expect(harness.localReads == localReads)
        #expect(store.repos.isEmpty)
        #expect(store.pulls.isEmpty)
        #expect(store.repoErrors.isEmpty)
        #expect(store.logins.isEmpty)
        #expect(store.selectedID == nil)
        #expect(store.badgeCount == 0)
        #expect(store.detailStore(for: item.repo.id) == nil)
        let onDisk = ReviewsSnapshotStore(directory: harness.directory).load()
        #expect(onDisk?.repos.isEmpty == true)
        #expect(onDisk?.pulls.isEmpty == true)

        // Nothing left to clear: the next refreshes write nothing.
        try FileManager.default.removeItem(at: harness.directory.appendingPathComponent("reviews.json"))
        await store.refresh(force: true)
        await store.refresh(force: true)
        #expect(ReviewsSnapshotStore(directory: harness.directory).load() == nil)
        #expect(harness.localReads == localReads)
    }

    @Test("Reloading a repo after a merge drops the merged pull request and lowers the count")
    func reloadAfterMerge() async {
        let harness = ReviewsHarness()
        harness.locals = [ReviewsHarness.local("team/app")]
        harness.provider.state {
            $0.lists["team/app"] = [ReviewsHarness.pr(1, by: "octo", updated: 100),
                                    ReviewsHarness.pr(2, by: "octo", updated: 200)]
        }
        let store = harness.makeStore()
        await store.refresh(force: true)
        #expect(store.badgeCount == 2)

        harness.provider.state { $0.lists["team/app"] = [ReviewsHarness.pr(2, by: "octo", updated: 200)] }
        await store.reload(repoKey: ReviewsHarness.key("team/app"))

        #expect(store.groups.flatMap(\.pulls).map(\.pull.number) == [2])
        #expect(store.badgeCount == 1)
        let onDisk = ReviewsSnapshotStore(directory: harness.directory).load()
        #expect(onDisk?.pulls[ReviewsHarness.key("team/app")]?.map(\.number) == [2])
    }

    @Test("A new store shows the last snapshot's groups before reading anything")
    func snapshotOnLaunch() async {
        let harness = ReviewsHarness.twoRepos()
        harness.provider.state {
            $0.lists["team/app"] = [ReviewsHarness.pr(1, by: "octo", updated: 100),
                                    ReviewsHarness.pr(2, by: "marta", updated: 300)]
            $0.lists["team/api"] = [ReviewsHarness.pr(3, by: "octo", updated: 200)]
        }
        let first = harness.makeStore()
        await first.refresh(force: true)
        let reads = Self.reads(harness)

        let next = harness.makeStore()
        next.loadSnapshot()

        #expect(next.groups.count == 2)
        #expect(next.groups == first.groups)
        #expect(next.badgeCount == 2)
        #expect(next.lastRefreshedAt == harness.now)
        next.filter = .mine
        #expect(next.groups.map { $0.pulls.map(\.pull.number) } == [[2]])
        #expect(Self.reads(harness) == reads)
        #expect(harness.browser.state { $0.listings } == 1)
    }

    @Test("Opening a pull request selects it in its repo's detail store, which loads it and is reused")
    func openDetail() async {
        let harness = ReviewsHarness()
        harness.locals = [ReviewsHarness.local("team/app")]
        harness.provider.state {
            $0.lists["team/app"] = [ReviewsHarness.pr(1, by: "octo", updated: 100),
                                    ReviewsHarness.pr(2, by: "octo", updated: 200)]
        }
        let store = harness.makeStore()
        await store.refresh(force: true)
        guard let first = store.groups.first?.pulls.first, let second = store.groups.first?.pulls.last,
              first.id != second.id else {
            Issue.record("Expected two rows in team/app")
            return
        }

        await store.open(first)
        let detail = store.detailStore(for: first.repo.id)
        #expect(detail?.selected?.number == first.pull.number)
        await waitUntil { detail?.detail != nil && detail?.isLoadingDetail == false }
        #expect(detail?.detail?.pull.number == first.pull.number)
        #expect(detail?.detailError == nil)

        await store.open(second)
        #expect(store.detailStore(for: second.repo.id) === detail)
        #expect(detail?.selected?.number == second.pull.number)
    }

    @Test("At most six lists are read at once, and every repo is read")
    func concurrencyLimit() async {
        let harness = ReviewsHarness()
        harness.locals = (0..<10).map { ReviewsHarness.local("team/repo\($0)") }
        harness.provider.state { state in
            state.delay = .milliseconds(20)
            for index in 0..<10 {
                state.lists["team/repo\(index)"] = [ReviewsHarness.pr(index + 1, by: "octo", updated: 1)]
            }
        }
        let store = harness.makeStore()
        await store.refresh(force: true)

        #expect(harness.provider.state { $0.mostRunning } <= ReviewsStore.concurrency)
        #expect(Self.reads(harness) == 10)
        #expect(store.badgeCount == 10)
    }

    @Test("A refresh cancelled while it reads the clones commits nothing, in memory or on disk")
    func cancelledRefreshCommitsNothing() async {
        let harness = ReviewsHarness.twoRepos()
        harness.provider.state {
            $0.lists["team/app"] = [ReviewsHarness.pr(1, by: "octo", updated: 100)]
            $0.lists["team/api"] = [ReviewsHarness.pr(2, by: "octo", updated: 200)]
        }
        let store = harness.makeStore()
        await store.refresh(force: true)
        let repos = store.repos
        let pulls = store.pulls
        let refreshedAt = store.lastRefreshedAt
        let onDisk = ReviewsSnapshotStore(directory: harness.directory).load()
        let reads = Self.reads(harness)
        #expect(onDisk != nil)

        // Cancelled, `GitCLI` reads no `origin`: the clones come back empty.
        let gate = AsyncGate()
        harness.localsGate = gate
        harness.locals = []
        harness.now = harness.now.addingTimeInterval(60)
        let round = Task { await store.refresh(force: true) }
        await gate.waiting()
        round.cancel()
        gate.open()
        await round.value

        #expect(store.repos == repos)
        #expect(store.pulls == pulls)
        #expect(store.lastRefreshedAt == refreshedAt)
        #expect(!store.isRefreshing)
        #expect(Self.reads(harness) == reads)
        #expect(ReviewsSnapshotStore(directory: harness.directory).load() == onDisk)

        // The cancelled round didn't count for the throttle.
        harness.localsGate = nil
        harness.locals = [ReviewsHarness.local("team/app")]
        harness.now = harness.now.addingTimeInterval(10)
        await store.refresh()
        #expect(Self.reads(harness) == reads + 2)
    }

    @Test("An account that needs attention keeps its repos and pull requests across refreshes, flagged")
    func needsAttentionKeepsRepos() async {
        let harness = ReviewsHarness.twoRepos()
        harness.provider.state {
            $0.lists["team/app"] = [ReviewsHarness.pr(1, by: "octo", updated: 100)]
            $0.lists["team/api"] = [ReviewsHarness.pr(2, by: "octo", updated: 200)]
        }
        let store = harness.makeStore()
        await store.refresh(force: true)
        let refreshedAt = store.lastRefreshedAt

        // Its token was rejected meanwhile, and the account store marked it.
        harness.account.status = .needsAttention(.revoked)
        for _ in 0..<2 {
            harness.now = harness.now.addingTimeInterval(60)
            await store.refresh(force: true)
            #expect(store.repos.map(\.host.repo).sorted() == ["api", "app"])
            #expect(store.groups.flatMap(\.pulls).map(\.pull.number).sorted() == [1, 2])
            #expect(store.accountsNeedingAttention == [harness.account.id])
        }
        // Nothing was read: the pull requests are as old as before.
        #expect(store.lastRefreshedAt == refreshedAt)
        let onDisk = ReviewsSnapshotStore(directory: harness.directory).load()
        #expect(onDisk?.pulls.values.flatMap { $0 }.count == 2)
    }

    @Test("A repo with no assignment and no owner's login goes to the usable account, not a dead one before it")
    func usableAccountFirst() async {
        let harness = ReviewsHarness()
        let usable = harness.account
        let dead = HostingAccount(instanceId: ReviewsHarness.instance.id, login: "octo", method: .oauth,
                                  status: .needsAttention(.expired))
        harness.accounts = [dead, usable]
        harness.locals = [ReviewsHarness.local("team/app")]
        harness.provider.state { $0.lists["team/app"] = [ReviewsHarness.pr(1, by: "lucia", updated: 1)] }
        let store = harness.makeStore()
        await store.refresh(force: true)

        #expect(store.repos.map(\.accountId) == [usable.id])
        #expect(store.badgeCount == 1)
        #expect(store.accountsNeedingAttention == [dead.id])
    }

    @Test("Without a stored login, the login is read once per session and drives the activity")
    func loginLookedUpOnce() async {
        let harness = ReviewsHarness.twoRepos(login: nil)
        harness.provider.state {
            $0.user = "marta"
            $0.lists["team/api"] = [ReviewsHarness.pr(1, by: "marta", updated: 1),
                                    ReviewsHarness.pr(2, by: "octo", updated: 2)]
        }
        let store = harness.makeStore()
        await store.refresh(force: true)
        await store.refresh(force: true)

        #expect(harness.provider.state { $0.userReads } == 1)
        #expect(harness.activity.state { $0.logins } == ["marta", "marta"])
        #expect(store.logins[harness.account.id] == "marta")
        #expect(store.repos.contains { $0.host.repo == "api" })
        #expect(store.badgeCount == 1)
    }

    // MARK: Clones and membership

    /// Clones of team/app (one open pull request) and oss/big (three), none of
    /// them the user's. The account belongs to `members` and nothing else;
    /// the clones are not members unless listed.
    private static func twoClones(members: [String]) -> ReviewsHarness {
        let harness = ReviewsHarness()
        harness.clonesAreMembers = false
        harness.locals = [ReviewsHarness.local("team/app"), ReviewsHarness.local("oss/big")]
        harness.browser.state {
            $0.members = members.enumerated().map { ReviewsHarness.member("m\($0.offset)", $0.element) }
        }
        harness.provider.state {
            $0.lists["team/app"] = [ReviewsHarness.pr(1, by: "octo", updated: 100)]
            $0.lists["oss/big"] = [ReviewsHarness.pr(2, by: "lucia", updated: 200),
                                   ReviewsHarness.pr(3, by: "jon", updated: 300),
                                   ReviewsHarness.pr(4, by: "ana", updated: 400)]
        }
        return harness
    }

    /// `count` repos of other people, none of them a clone.
    private static func fillers(_ count: Int) -> [String] { (0..<count).map { "org/repo-\($0)" } }

    private static func savedMembership(_ harness: ReviewsHarness) -> MembershipCache? {
        ReviewsSnapshotStore(directory: harness.directory).load()?.memberships[harness.account.id]
    }

    @Test("A clone of a repo the account doesn't belong to isn't followed: its pull requests aren't read or counted")
    func cloneOfAForeignRepoIsNotFollowed() async {
        let harness = Self.twoClones(members: ["team/app"])
        let store = harness.makeStore()
        await store.refresh(force: true)

        #expect(store.repos.map(\.host.repo) == ["app"])
        #expect(store.repos.first?.sources == [.local])
        #expect(harness.provider.state { $0.reads } == ["team/app"])
        #expect(store.pulls[ReviewsHarness.key("oss/big")] == nil)
        #expect(store.groups.map(\.repo.host.repo) == ["app"])
        #expect(store.badgeCount == 1)
        #expect(Self.savedMembership(harness)?.isComplete == true)
    }

    @Test("A clone among the account's repos is followed, whatever the case of its path")
    func cloneAmongTheMembersAnyCase() async {
        let harness = Self.twoClones(members: ["Team/App", "OSS/Big"])
        let store = harness.makeStore()
        await store.refresh(force: true)

        #expect(store.repos.map(\.host.repo).sorted() == ["app", "big"])
        #expect(store.badgeCount == 4)
    }

    @Test("A clone that stops being one of the account's repos leaves with its pull requests, error and detail store")
    func cloneLeavesWithTheMembership() async {
        let harness = Self.twoClones(members: ["team/app", "oss/big"])
        let store = harness.makeStore()
        await store.refresh(force: true)
        let big = ReviewsHarness.key("oss/big")
        #expect(store.repos.count == 2)
        #expect(store.badgeCount == 4)
        store.selectedID = "gitlab.example.test/oss/big#3"
        #expect(store.detailStore(for: big) != nil)

        harness.provider.state { $0.failures["oss/big"] = .notFound }
        await store.refresh(force: true)
        #expect(store.repoErrors[big] != nil)

        // A day later the membership is read again, and it no longer lists oss/big.
        harness.now = harness.now.addingTimeInterval(25 * 3600)
        harness.browser.state { $0.members = [ReviewsHarness.member("m0", "team/app")] }
        await store.refresh(force: true)

        #expect(store.repos.map(\.host.repo) == ["app"])
        #expect(store.pulls[big] == nil)
        #expect(store.repoErrors[big] == nil)
        #expect(store.detailStore(for: big) == nil)
        #expect(store.selectedID == nil)
        #expect(store.badgeCount == 1)
        #expect(ReviewsSnapshotStore(directory: harness.directory).load()?.pulls[big] == nil)
    }

    @Test("A clone is followed when the membership can't be read")
    func unreadableMembershipKeepsTheClones() async {
        let harness = Self.twoClones(members: ["team/app"])
        harness.browser.state { $0.failure = .network("The Internet connection appears to be offline.") }
        let store = harness.makeStore()
        await store.refresh(force: true)

        #expect(store.repos.map(\.host.repo).sorted() == ["app", "big"])
        #expect(store.badgeCount == 4)
        // Nothing was learnt about the account: no list is kept.
        #expect(Self.savedMembership(harness) == nil)
    }

    @Test("A clone is followed when the membership reached the page cap, since the list may be incomplete")
    func membershipAtThePageCapKeepsTheClones() async {
        let harness = Self.twoClones(members: Self.fillers(ReviewsStore.membershipPages * ReviewsFakeBrowser.pageSize))
        let store = harness.makeStore()
        await store.refresh(force: true)

        #expect(harness.browser.state { $0.mostPages } == ReviewsStore.membershipPages)
        #expect(store.repos.map(\.host.repo).sorted() == ["app", "big"])
        #expect(store.badgeCount == 4)
        #expect(Self.savedMembership(harness)?.repos.count == 500)
        #expect(Self.savedMembership(harness)?.isComplete == false)

        // The cached list is no more complete than when it was read.
        await store.refresh(force: true)
        #expect(harness.browser.state { $0.listings } == 1)
        #expect(store.repos.map(\.host.repo).sorted() == ["app", "big"])
    }

    @Test("A list that ends on an empty page just before the cap is complete, so it filters")
    func membershipJustUnderThePageCapFilters() async {
        // Nine full pages, then the tenth comes back empty.
        let members = Self.fillers((ReviewsStore.membershipPages - 1) * ReviewsFakeBrowser.pageSize - 1) + ["team/app"]
        let harness = Self.twoClones(members: members)
        let store = harness.makeStore()
        await store.refresh(force: true)

        #expect(members.count == 450)
        #expect(harness.browser.state { $0.mostPages } == ReviewsStore.membershipPages)
        #expect(Self.savedMembership(harness)?.isComplete == true)
        #expect(store.repos.map(\.host.repo) == ["app"])
        #expect(store.badgeCount == 1)
    }

    @Test("A dead account on the instance has no list and doesn't make the membership unknown")
    func deadAccountDoesNotMakeTheInstanceUnknown() async {
        let harness = Self.twoClones(members: ["team/app"])
        let usable = harness.account
        let dead = HostingAccount(instanceId: ReviewsHarness.instance.id, login: "octo", method: .oauth,
                                  status: .needsAttention(.revoked))
        harness.accounts.append(dead)
        let store = harness.makeStore()
        await store.refresh(force: true)

        #expect(store.accountsNeedingAttention == [dead.id])
        #expect(store.repos.map(\.host.repo) == ["app"])
        #expect(store.repos.map(\.accountId) == [usable.id])
        #expect(store.badgeCount == 1)
    }

    @Test("An instance with only dead accounts has no membership to filter by: its clones stay")
    func onlyDeadAccountsKeepTheClones() async {
        let harness = Self.twoClones(members: ["team/app"])
        harness.account.status = .needsAttention(.revoked)
        let store = harness.makeStore()
        await store.refresh(force: true)

        #expect(store.repos.map(\.host.repo).sorted() == ["app", "big"])
    }

    @Test("A clone is followed when any account that signs on the instance belongs to its repo")
    func membersOfSeveralAccountsAreJoined() async {
        let harness = Self.twoClones(members: [])
        let first = harness.account
        let second = HostingAccount(instanceId: ReviewsHarness.instance.id, login: "octo", method: .oauth, status: .ok)
        harness.accounts.append(second)
        harness.tokenFor = [first.id: .token("first"), second.id: .token("second")]
        harness.browser.state {
            $0.membersByToken = ["first": [ReviewsHarness.member("m0", "team/app")],
                                 "second": [ReviewsHarness.member("m1", "oss/big")]]
        }
        let store = harness.makeStore()
        await store.refresh(force: true)

        #expect(store.repos.map(\.host.repo).sorted() == ["app", "big"])

        // Without the second account, oss/big has nobody.
        harness.accounts.removeLast()
        harness.now = harness.now.addingTimeInterval(60)
        await store.refresh(force: true)
        #expect(store.repos.map(\.host.repo) == ["app"])
    }

    @Test("A clone is followed when an account that signs has no list to read, even if the other one's lacks it")
    func oneUnreadableListMakesTheInstanceUnknown() async {
        let harness = Self.twoClones(members: [])
        let first = harness.account
        let second = HostingAccount(instanceId: ReviewsHarness.instance.id, login: "octo", method: .oauth, status: .ok)
        harness.accounts.append(second)
        // The second account's token can't be had for now (offline), so its list isn't read.
        harness.tokenFor = [first.id: .token("first"), second.id: .failed("offline")]
        harness.browser.state { $0.membersByToken = ["first": [ReviewsHarness.member("m0", "team/app")]] }
        let store = harness.makeStore()
        await store.refresh(force: true)

        #expect(store.repos.map(\.host.repo).sorted() == ["app", "big"])
    }

    /// Saves a snapshot that holds only the account's membership, as an earlier
    /// build wrote it: no word on whether the list is complete.
    private static func seedMembership(_ harness: ReviewsHarness, repos: [String]) throws {
        let cached = MembershipCache(fetchedAt: harness.now.addingTimeInterval(-3600),
                                     repos: repos.enumerated().map {
                                         ReviewsHarness.member("c\($0.offset)", $0.element)
                                     })
        let snapshot = ReviewsSnapshot(version: ReviewsSnapshot.currentVersion,
                                       savedAt: harness.now.addingTimeInterval(-3600), repos: [], pulls: [:],
                                       memberships: [harness.account.id: cached], logins: [:])
        ReviewsSnapshotStore(directory: harness.directory).save(snapshot)
        let text = try String(contentsOf: harness.directory.appendingPathComponent("reviews.json"), encoding: .utf8)
        #expect(!text.contains("isComplete"))
    }

    @Test("A cached list saved without its completeness is complete below the page cap, so it filters",
          arguments: [1, 499])
    func cachedListWithoutCompletenessFilters(count: Int) async throws {
        let harness = Self.twoClones(members: [])
        try Self.seedMembership(harness, repos: ["team/app"] + Self.fillers(count - 1))
        let store = harness.makeStore()
        store.loadSnapshot()
        await store.refresh(force: true)

        #expect(harness.browser.state { $0.listings } == 0)
        #expect(store.repos.map(\.host.repo) == ["app"])
        #expect(store.badgeCount == 1)
    }

    @Test("A cached list saved without its completeness that fills the page cap may be incomplete, so the clones stay")
    func cachedListWithoutCompletenessAtTheCapKeepsTheClones() async throws {
        let harness = Self.twoClones(members: [])
        try Self.seedMembership(harness, repos: ["team/app"] + Self.fillers(499))
        let store = harness.makeStore()
        store.loadSnapshot()
        await store.refresh(force: true)

        #expect(harness.browser.state { $0.listings } == 0)
        #expect(store.repos.map(\.host.repo).sorted() == ["app", "big"])
    }

    // MARK: Selection

    @Test("A selection the filter still shows stays; one it hides, or that left, goes without another taking its place")
    func selectionHygiene() async {
        let harness = ReviewsHarness.twoRepos()
        harness.provider.state {
            $0.lists["team/app"] = [ReviewsHarness.pr(1, by: "octo", updated: 100),
                                    ReviewsHarness.pr(2, by: "marta", updated: 300)]
            $0.lists["team/api"] = [ReviewsHarness.pr(3, by: "octo", updated: 200),
                                    ReviewsHarness.pr(4, by: "octo", state: .draft, updated: 150)]
        }
        let store = harness.makeStore()
        await store.refresh(force: true)
        let three = "gitlab.example.test/team/api#3"

        store.selectedID = three
        #expect(store.selectedItem?.pull.number == 3)
        store.dropHiddenSelection()
        #expect(store.selectedID == three)

        // Mine doesn't show it: nothing is selected, not the first of Mine.
        store.filter = .mine
        #expect(store.selectedItem == nil)
        store.dropHiddenSelection()
        #expect(store.selectedID == nil)

        // Back in Team, a pull request that leaves with a reload goes too.
        store.filter = .team
        store.selectedID = three
        harness.provider.state {
            $0.lists["team/api"] = [ReviewsHarness.pr(4, by: "octo", state: .draft, updated: 150)]
        }
        await store.reload(repoKey: ReviewsHarness.key("team/api"))
        #expect(store.selectedItem == nil)
        store.dropHiddenSelection()
        #expect(store.selectedID == nil)
    }

    @Test("The accounts to reconnect come with their instance; the ones that sign don't")
    func accountsToReconnect() async {
        let harness = ReviewsHarness.twoRepos()
        let dead = HostingAccount(instanceId: ReviewsHarness.instance.id, login: "octo", method: .oauth,
                                  status: .needsAttention(.revoked))
        harness.accounts.append(dead)
        // The clone of team/app is read with the dead account: its repo stays listed.
        harness.locals = [ReviewsHarness.local("team/app", account: dead.id)]
        let store = harness.makeStore()
        #expect(store.accountsToReconnect.isEmpty)

        await store.refresh(force: true)

        #expect(store.repos.first { $0.host.repo == "app" }?.accountId == dead.id)
        #expect(store.accountsToReconnect.map(\.account.id) == [dead.id])
        #expect(store.accountsToReconnect.map(\.instance.id) == [ReviewsHarness.instance.id])
        // Removed meanwhile: no notice for an account that's gone.
        harness.accounts.removeLast()
        #expect(store.accountsToReconnect.isEmpty)
    }

    @Test("A dead account that owns no followed repo needs attention but gets no reconnect notice")
    func deadAccountWithoutReposHasNoNotice() async {
        let harness = ReviewsHarness.twoRepos()
        let dead = HostingAccount(instanceId: ReviewsHarness.instance.id, login: "octo", method: .oauth,
                                  status: .needsAttention(.revoked))
        harness.accounts.append(dead)
        let store = harness.makeStore()

        await store.refresh(force: true)

        #expect(store.accountsNeedingAttention == [dead.id])
        #expect(store.repos.map(\.host.repo).sorted() == ["api", "app"])
        #expect(store.repos.allSatisfy { $0.accountId != dead.id })
        #expect(store.accountsToReconnect.isEmpty)
    }

    @Test("An account that goes dead keeps its notice while its repos stay, until it's connected again")
    func carriedOverReposKeepTheNotice() async {
        let harness = ReviewsHarness.twoRepos()
        harness.provider.state {
            $0.lists["team/app"] = [ReviewsHarness.pr(1, by: "octo", updated: 100)]
            $0.lists["team/api"] = [ReviewsHarness.pr(2, by: "octo", updated: 200)]
        }
        let store = harness.makeStore()
        await store.refresh(force: true)
        #expect(store.accountsToReconnect.isEmpty)

        // Its token was rejected meanwhile: both repos (a clone and a carried-over activity one) stay.
        harness.account.status = .needsAttention(.revoked)
        harness.now = harness.now.addingTimeInterval(60)
        await store.refresh(force: true)
        #expect(store.repos.count == 2)
        #expect(store.accountsToReconnect.map(\.account.id) == [harness.account.id])

        // Connected again.
        harness.account.status = .ok
        harness.now = harness.now.addingTimeInterval(60)
        await store.refresh(force: true)
        #expect(store.accountsNeedingAttention.isEmpty)
        #expect(store.accountsToReconnect.isEmpty)
    }
}

@Suite("Reviews inbox — detail")
struct ReviewsDetailRulesTests {
    private static func repo(localURL: URL?) -> ReviewRepo {
        ReviewRepo(host: RemoteHost(provider: .gitlab, host: "gitlab.example.test", owner: "apps/payments", repo: "ledger"),
                   accountId: UUID(), sources: [.activity], lastActivity: nil,
                   cloneURL: "https://gitlab.example.test/apps/payments/ledger.git", localURL: localURL)
    }

    @Test("A repo that isn't on this Mac offers to clone it with its clone URL; a clone, to open it")
    func repoAction() {
        #expect(ReviewRepoAction(Self.repo(localURL: nil)) == .clone(url: "https://gitlab.example.test/apps/payments/ledger.git"))
        let clone = URL(fileURLWithPath: "/Users/marta/Developer/ledger")
        #expect(ReviewRepoAction(Self.repo(localURL: clone)) == .openInRepository(clone))
    }

    @Test("Only the same pull request leaving open or draft, with its merge over, reloads its repo")
    func leftOpen() {
        func state(_ id: String, _ state: PullRequest.State, merging: Bool = false) -> ReviewDetailState {
            ReviewDetailState(itemID: id, state: state, isMerging: merging)
        }
        #expect(ReviewDetailState.leftOpen(from: state("a#1", .open), to: state("a#1", .merged)))
        #expect(ReviewDetailState.leftOpen(from: state("a#1", .draft), to: state("a#1", .closed)))
        // The merge sheet is still reading the result back.
        #expect(!ReviewDetailState.leftOpen(from: state("a#1", .open), to: state("a#1", .merged, merging: true)))
        #expect(ReviewDetailState.leftOpen(from: state("a#1", .merged, merging: true), to: state("a#1", .merged)))
        // Another pull request, or none.
        #expect(!ReviewDetailState.leftOpen(from: state("a#1", .open), to: state("b#2", .merged)))
        #expect(!ReviewDetailState.leftOpen(from: state("a#1", .open), to: nil))
        #expect(!ReviewDetailState.leftOpen(from: nil, to: state("a#1", .merged)))
        #expect(!ReviewDetailState.leftOpen(from: state("a#1", .open), to: state("a#1", .draft)))
    }
}
