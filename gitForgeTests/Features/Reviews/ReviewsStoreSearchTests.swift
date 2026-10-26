import Foundation
import Testing
@testable import gitForge

/// "Search all of <host>", the repos found that way and the link kept until
/// an account is connected (R3 Rulings 12 to 14).
@Suite("Reviews store — searching a whole host, found repos and the pending link")
@MainActor
struct ReviewsStoreSearchTests {
    private static let app = ReviewsHarness.key("team/app")
    private static let lib = ReviewsHarness.key("oss/lib")
    private static let own = ReviewsHarness.instance.id

    /// The row id of pull request `number` in the repo with key `repo`.
    private static func id(_ repo: String, _ number: Int) -> InboxPull.ID { "\(repo)#\(number)" }

    private static func link(_ path: String, _ number: Int) -> PullRequestLink {
        PullRequestLink(host: ReviewsHarness.host(path), number: number, instanceId: own)
    }

    /// A link on `code.example.test`, an instance without accounts.
    private static func linkElsewhere() -> PullRequestLink {
        let elsewhere = HostingInstance(kind: .gitlab, host: "code.example.test")
        return PullRequestLink(host: RemoteHost.make(fullName: "oss/lib", on: elsewhere)!, number: 1,
                               instanceId: elsewhere.id)
    }

    /// `path` as a search finds it, cloned from a URL no membership gives.
    private static func found(_ path: String) -> FoundRepo {
        FoundRepo(host: ReviewsHarness.host(path), instanceId: own,
                  cloneURL: "https://gitlab.example.test/found/\(path).git")
    }

    private static func foundPull(_ path: String, _ number: Int, title: String) -> FoundPull {
        FoundPull(link: link(path, number), title: title, authorLogin: "octo",
                  updatedAt: ReviewsHarness.date(1_789_000_000), isDraft: false)
    }

    private static func searches(_ harness: ReviewsHarness) -> [ReviewsFakeSearch.SearchCall] {
        harness.search.state { $0.searches }
    }

    /// The searches made so far, forgotten for the next check.
    private static func takeSearches(_ harness: ReviewsHarness) -> [ReviewsFakeSearch.SearchCall] {
        harness.search.state { state in
            defer { state.searches = [] }
            return state.searches
        }
    }

    private static func listings(_ harness: ReviewsHarness) -> Int { harness.browser.state { $0.listings } }

    private static func reads(_ harness: ReviewsHarness) -> [String] { harness.provider.state { $0.reads } }

    /// An account on `instance` whose token is `token` and whose membership lists `members`.
    @discardableResult
    private static func addAccount(to harness: ReviewsHarness, on instance: HostingInstance, login: String,
                                   token: String, members: [String] = []) -> HostingAccount {
        let account = HostingAccount(instanceId: instance.id, login: login, method: .oauth, status: .ok)
        harness.accounts.append(account)
        harness.tokenFor[account.id] = .token(token)
        let summaries = members.enumerated().map { ReviewsHarness.member("\(token)-\($0.offset)", $0.element) }
        harness.browser.state { $0.membersByToken[token] = summaries }
        return account
    }

    /// Whether `calls` are one search of pull requests and one of repos, for
    /// `text` under `owners`.
    private static func isPair(_ calls: [ReviewsFakeSearch.SearchCall], text: String, owners: [String]?) -> Bool {
        calls.count == 2 && calls.contains { $0.kind == .pulls } && calls.contains { $0.kind == .repos }
            && calls.allSatisfy { $0.text == text && $0.owners == owners }
    }

    /// team/app (a clone) and team/api (activity) read; oss/lib, which isn't
    /// followed, has !5 by `octo` and !6 by `marta` open.
    private static func loaded() async -> (store: ReviewsStore, harness: ReviewsHarness) {
        let harness = ReviewsHarness.twoRepos()
        harness.provider.state {
            $0.lists["team/app"] = [ReviewsHarness.pr(1, by: "octo", updated: 100)]
            $0.lists["team/api"] = [ReviewsHarness.pr(2, by: "octo", updated: 200)]
            $0.lists["oss/lib"] = [ReviewsHarness.pr(5, by: "octo", updated: 300),
                                   ReviewsHarness.pr(6, by: "marta", updated: 250)]
        }
        let store = harness.makeStore()
        await store.refresh(force: true)
        return (store, harness)
    }

    // MARK: Instances and owners

    @Test("Each instance with an account in the inbox can be searched, once, in the order of the accounts")
    func searchInstances() {
        let harness = ReviewsHarness()
        Self.addAccount(to: harness, on: .gitHubDotCom, login: "octo", token: "t-gh")
        harness.accounts.append(HostingAccount(instanceId: Self.own, login: "ana", method: .oauth, status: .ok))
        let store = harness.makeStore()

        #expect(store.searchInstances.map(\.id) == [Self.own, HostingInstance.gitHubDotCom.id])
    }

    @Test("The owners searched are the five with most repos, by name when tied, once each whatever their case")
    func ownersCut() {
        let paths = ["octo/a", "Octo/b", "octo/c", "ops/a", "ops/b", "ana/a", "zed/a", "kit/a", "lab/a", "marta/a"]
        let members = paths.enumerated().map { ReviewsHarness.member("\($0.offset)", $0.element) }

        #expect(ReviewsStore.searchOwners(on: .gitHubDotCom, members: members, login: "marta")
                == ["octo", "ops", "ana", "kit", "lab"])
        // On GitLab the login's namespace isn't a group.
        #expect(ReviewsStore.searchOwners(on: .gitLabDotCom, members: members, login: "ana")
                == ["octo", "ops", "kit", "lab", "marta"])
        // An instance of the user's own isn't scoped.
        #expect(ReviewsStore.searchOwners(on: ReviewsHarness.instance, members: members, login: "marta") == nil)
    }

    // MARK: Searching

    @Test("An instance of the user's own searches everything the account sees, with the query trimmed")
    func ownInstanceUnscoped() async {
        let harness = ReviewsHarness()
        let pull = Self.foundPull("oss/lib", 5, title: "Fix retry")
        let repo = Self.found("oss/lib")
        harness.search.state {
            $0.pulls = [pull]
            $0.repos = [repo]
        }
        let store = harness.makeStore()

        // Under three characters once trimmed, nothing is asked.
        await store.searchHost(Self.own, query: "  li \n")
        #expect(store.hostSearches.isEmpty)
        #expect(Self.searches(harness).isEmpty)

        await store.searchHost(Self.own, query: "  lib \n")

        #expect(store.hostSearches[Self.own]
                == HostSearchState(query: "lib", phase: .found(HostSearchResults(pulls: [pull], repos: [repo]))))
        #expect(Self.isPair(Self.searches(harness), text: "lib", owners: nil))
        #expect(Self.listings(harness) == 0)
    }

    @Test("On github.com and gitlab.com a search keeps to the owners of the account's repos, the login out on GitLab")
    func dotComScoped() async {
        let harness = ReviewsHarness()
        Self.addAccount(to: harness, on: .gitHubDotCom, login: "marta", token: "t-gh",
                        members: ["octo/a", "octo/b", "octo/c", "ops/tools", "marta/notes"])
        Self.addAccount(to: harness, on: .gitLabDotCom, login: "marta", token: "t-gl",
                        members: ["octo/a", "octo/infra/b", "marta/notes", "ops/tools"])
        let store = harness.makeStore()

        await store.searchHost(HostingInstance.gitHubDotCom.id, query: "lib")
        #expect(Self.isPair(Self.takeSearches(harness), text: "lib", owners: ["octo", "marta", "ops"]))
        #expect(Self.listings(harness) == 1)

        await store.searchHost(HostingInstance.gitLabDotCom.id, query: "lib")
        #expect(Self.isPair(Self.takeSearches(harness), text: "lib", owners: ["octo", "ops"]))
        #expect(Self.listings(harness) == 2)

        // The lists read stay: searching again reads none.
        await store.searchHost(HostingInstance.gitHubDotCom.id, query: "app")
        #expect(Self.isPair(Self.takeSearches(harness), text: "app", owners: ["octo", "marta", "ops"]))
        #expect(Self.listings(harness) == 2)
    }

    @Test("On github.com or gitlab.com, an account with no owner to search under finds nothing, without asking")
    func dotComWithoutOwners() async {
        let harness = ReviewsHarness()
        Self.addAccount(to: harness, on: .gitHubDotCom, login: "marta", token: "t-gh")
        Self.addAccount(to: harness, on: .gitLabDotCom, login: "marta", token: "t-gl", members: ["marta/notes"])
        let store = harness.makeStore()

        await store.searchHost(HostingInstance.gitHubDotCom.id, query: "lib")
        await store.searchHost(HostingInstance.gitLabDotCom.id, query: "lib")

        let nothing = HostSearchState(query: "lib", phase: .found(HostSearchResults()))
        #expect(store.hostSearches[HostingInstance.gitHubDotCom.id] == nothing)
        #expect(store.hostSearches[HostingInstance.gitLabDotCom.id] == nothing)
        #expect(Self.searches(harness).isEmpty)
        #expect(Self.listings(harness) == 2)
    }

    @Test("On github.com or gitlab.com, an unreadable membership list fails the search; one of any age is used as is")
    func dotComMembershipUnread() async {
        let harness = ReviewsHarness()
        let github = HostingInstance.gitHubDotCom.id
        Self.addAccount(to: harness, on: .gitHubDotCom, login: "marta", token: "t-gh", members: ["octo/a"])
        let offline = PullRequestFetchError.network("The Internet connection appears to be offline.")
        harness.browser.state { $0.failure = offline }
        let store = harness.makeStore()

        await store.searchHost(github, query: "lib")

        let failed = HostSearchState(query: "lib", phase: .failed(PullRequestStore.message(for: offline)))
        #expect(store.hostSearches[github] == failed)
        #expect(Self.searches(harness).isEmpty)

        // Once read, the list is used however old it gets, without reading it again.
        harness.browser.state { $0.failure = nil }
        await store.searchHost(github, query: "lib")
        #expect(Self.isPair(Self.takeSearches(harness), text: "lib", owners: ["octo"]))
        harness.browser.state { $0.failure = offline }
        harness.now = harness.now.addingTimeInterval(2 * ReviewsStore.membershipTTL)
        await store.searchHost(github, query: "app")
        #expect(Self.isPair(Self.takeSearches(harness), text: "app", owners: ["octo"]))
        #expect(Self.listings(harness) == 2)
    }

    @Test("Without an account of the instance that signs, the search asks to connect one, without a request")
    func noSigningAccount() async {
        let harness = ReviewsHarness()
        harness.account.status = .needsAttention(.expired)
        let store = harness.makeStore()

        await store.searchHost(Self.own, query: "lib")

        #expect(store.hostSearches[Self.own] == HostSearchState(query: "lib", phase: .connectAccount))
        #expect(Self.searches(harness).isEmpty)
    }

    @Test("Once the sheet to connect an account closes, the searches that asked for one go; the others stay")
    func forgetConnectSearches() async {
        let harness = ReviewsHarness()
        harness.account.status = .needsAttention(.expired)
        Self.addAccount(to: harness, on: .gitHubDotCom, login: "marta", token: "t-gh")
        let store = harness.makeStore()
        await store.searchHost(Self.own, query: "lib")
        await store.searchHost(HostingInstance.gitHubDotCom.id, query: "lib")
        let nothing = HostSearchState(query: "lib", phase: .found(HostSearchResults()))
        #expect(store.hostSearches[Self.own] == HostSearchState(query: "lib", phase: .connectAccount))
        #expect(store.hostSearches[HostingInstance.gitHubDotCom.id] == nothing)

        store.forgetConnectSearches()

        #expect(store.hostSearches[Self.own] == nil)
        #expect(store.hostSearches[HostingInstance.gitHubDotCom.id] == nothing)
    }

    @Test("A search whose token is rejected renews it once; rejected again, it asks to connect the account")
    func searchRejected() async {
        let harness = ReviewsHarness()
        harness.search.state { $0.failure = .unauthorized }
        let store = harness.makeStore()

        await store.searchHost(Self.own, query: "lib")

        #expect(store.hostSearches[Self.own] == HostSearchState(query: "lib", phase: .connectAccount))
        #expect(harness.renewals == ["t"])
        #expect(Self.searches(harness).count == 4)
    }

    @Test("A search that fails says why")
    func searchFailed() async {
        let harness = ReviewsHarness()
        harness.search.state { $0.failure = .server(500, "") }
        let store = harness.makeStore()

        await store.searchHost(Self.own, query: "lib")

        let message = PullRequestStore.message(for: PullRequestFetchError.server(500, ""))
        #expect(store.hostSearches[Self.own] == HostSearchState(query: "lib", phase: .failed(message)))
    }

    @Test("A newer search of the instance wins: an older one that lands later changes nothing")
    func laterSearchWins() async {
        let harness = ReviewsHarness()
        let held = AsyncGate()
        let newer = Self.foundPull("oss/lib", 5, title: "Newer")
        harness.search.state {
            $0.gates["first"] = held
            $0.pulls = [newer]
        }
        let store = harness.makeStore()

        let first = Task { await store.searchHost(Self.own, query: "first") }
        await held.waiting()
        #expect(store.hostSearches[Self.own] == HostSearchState(query: "first", phase: .searching))

        await store.searchHost(Self.own, query: "second")
        let second = HostSearchState(query: "second", phase: .found(HostSearchResults(pulls: [newer])))
        #expect(store.hostSearches[Self.own] == second)

        // The older one answers, with other results, too late.
        harness.search.state { $0.pulls = [Self.foundPull("oss/lib", 6, title: "Older")] }
        held.open()
        await first.value
        #expect(store.hostSearches[Self.own] == second)
    }

    // MARK: Found repos

    @Test("A found repo the inbox follows narrows the inbox to it, without reading anything")
    func openFollowedRepo() async {
        let (store, harness) = await Self.loaded()
        let before = Self.reads(harness)

        let outcome = await store.openFoundRepo(Self.found("team/app"))

        #expect(outcome == .shown(repoKey: Self.app))
        #expect(store.repoFilter == Self.app)
        #expect(store.browsedRepos.isEmpty)
        #expect(Self.reads(harness) == before)
        #expect(store.followedKeys == [Self.app, ReviewsHarness.key("team/api")])
    }

    @Test("A found repo the inbox doesn't follow opens with its open pull requests among the Others, narrowed to it")
    func openUnfollowedRepo() async throws {
        let (store, harness) = await Self.loaded()
        store.selectedID = Self.id(Self.app, 1)
        store.filter = .mine

        let outcome = await store.openFoundRepo(Self.found("oss/lib"))

        #expect(outcome == .shown(repoKey: Self.lib))
        #expect(store.repoFilter == Self.lib)
        #expect(store.filteredRepo?.id == Self.lib)
        // The selection was on another repo.
        #expect(store.selectedID == nil)
        // One group with both halves, newest first.
        let both = [Self.id(Self.lib, 5), Self.id(Self.lib, 6)]
        #expect(store.groups.map(\.id) == [Self.lib])
        #expect(store.groups.first?.pulls.map(\.id) == both)
        #expect(store.visibleOthers.isEmpty)
        #expect(store.listContent == .groups(store.groups, others: []))
        #expect(store.others.map(\.id) == both)
        #expect(!store.repos.contains { $0.id == Self.lib })
        let browsed = try #require(store.browsedRepos.first)
        #expect(store.browsedRepos.count == 1)
        #expect(browsed.id == Self.lib)
        #expect(browsed.sources.isEmpty)
        #expect(browsed.accountId == harness.account.id)
        #expect(browsed.cloneURL == "https://gitlab.example.test/found/oss/lib.git")
        #expect(store.others.allSatisfy { $0.repo == browsed })

        // Shown again, every repo: its pull requests stay among the Others,
        // each under the half of its author.
        store.showAllRepos()
        #expect(store.filter == .mine)
        #expect(store.visibleOthers.map(\.id) == [Self.id(Self.lib, 6)])
        store.filter = .team
        #expect(store.visibleOthers.map(\.id) == [Self.id(Self.lib, 5)])
    }

    @Test("Closing the repo filter with an Other of the browsed repo selected goes to the half that shows it")
    func closingFilterOnOther() async {
        let (store, _) = await Self.loaded()
        _ = await store.openFoundRepo(Self.found("oss/lib"))
        store.filter = .team
        store.selectedID = Self.id(Self.lib, 6)

        store.showAllRepos()

        #expect(store.repoFilter == nil)
        #expect(store.filter == .mine)
        #expect(store.selectedItem?.id == Self.id(Self.lib, 6))
        #expect(store.revealRequest?.id == Self.id(Self.lib, 6))
    }

    @Test("A link to a pull request of the browsed repo selects it and keeps the inbox narrowed to the repo")
    func linkInBrowsedRepo() async {
        let (store, _) = await Self.loaded()
        _ = await store.openFoundRepo(Self.found("oss/lib"))

        let outcome = await store.openLink(Self.link("oss/lib", 6))

        #expect(outcome == .opened(Self.id(Self.lib, 6)))
        #expect(store.selectedItem?.id == Self.id(Self.lib, 6))
        #expect(store.repoFilter == Self.lib)
        #expect(store.revealRequest?.id == Self.id(Self.lib, 6))
    }

    @Test("A found repo with no open pull requests is shown narrowed to, empty, also while a refresh runs")
    func openEmptyRepo() async {
        let (store, harness) = await Self.loaded()
        harness.provider.state { $0.lists["oss/lib"] = nil }

        let outcome = await store.openFoundRepo(Self.found("oss/lib"))

        #expect(outcome == .shown(repoKey: Self.lib))
        #expect(store.filteredRepo?.id == Self.lib)
        #expect(store.groups.isEmpty)
        #expect(store.listContent == .empty)

        let reading = AsyncGate()
        harness.localsGate = reading
        let round = Task { await store.refresh(force: true) }
        await reading.waiting()
        #expect(store.isRefreshing)
        #expect(store.listContent == .empty)

        reading.open()
        await round.value
        #expect(store.filteredRepo?.id == Self.lib)
        #expect(store.listContent == .empty)
    }

    @Test("A found repo no account can see isn't opened, and the message names it")
    func openHiddenRepo() async {
        let (store, harness) = await Self.loaded()
        let ana = HostingAccount(instanceId: Self.own, login: "ana", method: .oauth, status: .ok)
        harness.accounts.append(ana)
        harness.tokenFor[ana.id] = .token("t-ana")
        harness.provider.state { $0.failures["oss/lib"] = .notFound }

        let outcome = await store.openFoundRepo(Self.found("oss/lib"))

        let message = PullRequestStore.message(for: PullRequestFetchError.notFound)
        #expect(outcome == .failed("oss/lib — \(message)"))
        #expect(Self.reads(harness).filter { $0 == "oss/lib" }.count == 2)
        #expect(store.browsedRepos.isEmpty)
        #expect(store.repoFilter == nil)
        #expect(store.others.isEmpty)
    }

    @Test("A found repo whose only account must be connected again asks to connect it")
    func openRepoConnect() async {
        let harness = ReviewsHarness()
        harness.account.status = .needsAttention(.expired)
        let store = harness.makeStore()

        let outcome = await store.openFoundRepo(Self.found("oss/lib"))

        #expect(outcome == .connectAccount(instanceId: Self.own))
        #expect(store.browsedRepos.isEmpty)
        #expect(Self.reads(harness).isEmpty)
    }

    @Test("Following a browsed repo moves it to the followed ones, and the inbox stays narrowed to it")
    func followBrowsed() async {
        let (store, _) = await Self.loaded()
        let found = Self.found("oss/lib")
        _ = await store.openFoundRepo(found)

        let outcome = await store.follow(found)

        #expect(outcome == .done)
        #expect(store.repos.first { $0.id == Self.lib }?.sources == [.manual])
        #expect(store.followedKeys.contains(Self.lib))
        #expect(store.browsedRepos.isEmpty)
        #expect(store.repoFilter == Self.lib)
        #expect(store.filteredRepo?.sources == [.manual])
        #expect(store.groups.first?.pulls.map(\.id) == [Self.id(Self.lib, 5), Self.id(Self.lib, 6)])

        // Rows of the followed list now, they no longer show as Others.
        store.showAllRepos()
        #expect(store.visibleOthers.isEmpty)
    }

    // MARK: Pending link

    @Test("A link that asked to connect an account is opened again once, when an account of its instance signs")
    func pendingLink() async {
        let harness = ReviewsHarness()
        let marta = harness.account
        harness.accounts = []
        harness.provider.state {
            $0.lists["oss/lib"] = [ReviewsHarness.pr(5, by: "octo", updated: 300),
                                   ReviewsHarness.pr(6, by: "octo", updated: 250)]
        }
        let store = harness.makeStore()
        let link = Self.link("oss/lib", 5)

        let unread = await store.openLink(link)
        #expect(unread == .connectAccount(instanceId: Self.own))
        #expect(store.pendingLink == link)

        // Still no account: it's dropped.
        let dropped = await store.retryPendingLink()
        #expect(dropped == nil)
        #expect(store.pendingLink == nil)

        _ = await store.openLink(link)
        #expect(store.pendingLink == link)
        harness.accounts = [marta]
        let opened = await store.retryPendingLink()
        #expect(opened == .opened(Self.id(Self.lib, 5)))
        #expect(store.pendingLink == nil)
        #expect(store.selectedID == Self.id(Self.lib, 5))

        // A later link clears it, whatever it comes to.
        let elsewhere = Self.linkElsewhere()
        _ = await store.openLink(elsewhere)
        #expect(store.pendingLink == elsewhere)
        _ = await store.openLink(link)
        #expect(store.pendingLink == nil)

        // Opened again once: one that asks for an account again isn't kept.
        harness.tokenFor[marta.id] = .connectAccount(instanceId: Self.own, replacing: marta.id)
        let six = Self.link("oss/lib", 6)
        _ = await store.openLink(six)
        #expect(store.pendingLink == six)
        let again = await store.retryPendingLink()
        #expect(again == .connectAccount(instanceId: Self.own))
        #expect(store.pendingLink == nil)
    }

    @Test("A link pasted before any account is connected outlives the refresh Reviews makes, and opens once one is")
    func pendingLinkBeforeFirstAccount() async {
        let harness = ReviewsHarness()
        let marta = harness.account
        harness.accounts = []
        harness.provider.state { $0.lists["oss/lib"] = [ReviewsHarness.pr(5, by: "octo", updated: 300)] }
        let store = harness.makeStore()
        let link = Self.link("oss/lib", 5)

        let unread = await store.openLink(link)
        #expect(unread == .connectAccount(instanceId: Self.own))
        // Reviews shows up and refreshes, without accounts.
        await store.refresh()
        #expect(store.pendingLink == link)

        harness.accounts = [marta]
        let opened = await store.retryPendingLink()

        #expect(opened == .opened(Self.id(Self.lib, 5)))
        #expect(store.pendingLink == nil)
        #expect(store.selectedID == Self.id(Self.lib, 5))
    }

    // MARK: Without accounts

    @Test("Without accounts the browsed repos and the searches go; the pending link stays, waiting for one")
    func clearedWithoutAccounts() async {
        let (store, harness) = await Self.loaded()
        _ = await store.openFoundRepo(Self.found("oss/lib"))
        await store.searchHost(Self.own, query: "lib")
        let elsewhere = Self.linkElsewhere()
        _ = await store.openLink(elsewhere)
        #expect(!store.browsedRepos.isEmpty)
        #expect(!store.hostSearches.isEmpty)
        #expect(store.pendingLink == elsewhere)

        harness.accounts = []
        await store.refresh(force: true)

        #expect(store.browsedRepos.isEmpty)
        #expect(store.hostSearches.isEmpty)
        #expect(store.pendingLink == elsewhere)
        #expect(store.repoFilter == nil)
        #expect(store.filteredRepo == nil)
    }
}
