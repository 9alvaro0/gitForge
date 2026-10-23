import Foundation
import Testing
@testable import gitForge

@Suite("Reviews store — patterns, manual and hidden repos")
@MainActor
struct ReviewsStoreFollowTests {
    // MARK: Helpers

    private static func pattern(_ text: String) -> FollowPattern {
        FollowPattern(host: ReviewsHarness.instance.host, text: text)!
    }

    private static func found(_ path: String) -> FoundRepo {
        FoundRepo(host: ReviewsHarness.host(path), instanceId: ReviewsHarness.instance.id,
                  cloneURL: "https://gitlab.example.test/\(path).git")
    }

    /// The settings on disk, as a new store would read them.
    private static func saved(_ harness: ReviewsHarness) -> ReviewsConfig {
        ReviewsConfigStore(directory: harness.directory).load()
    }

    /// Writes the settings a store made afterwards starts with.
    private static func save(_ config: ReviewsConfig, in harness: ReviewsHarness) {
        ReviewsConfigStore(directory: harness.directory).save(config)
    }

    private static func listings(_ harness: ReviewsHarness) -> Int { harness.browser.state { $0.listings } }

    private static func reads(_ harness: ReviewsHarness) -> [String] { harness.provider.state { $0.reads } }

    private static func repo(_ store: ReviewsStore, _ path: String) -> ReviewRepo? {
        store.repos.first { $0.id == ReviewsHarness.key(path) }
    }

    private static func slugs(_ store: ReviewsStore) -> [String] { store.repos.map(\.host.slug).sorted() }

    /// A member whose clone URL isn't the one `FollowedRepos.cloneURL(for:)` would make.
    private static func member(_ id: String, _ path: String, cloneName: String) -> RemoteRepoSummary {
        RemoteRepoSummary(id: id, name: cloneName, fullName: path, description: nil, sshURL: nil,
                          httpsURL: "https://gitlab.example.test/clone/\(cloneName).git", isPrivate: true,
                          defaultBranch: "main")
    }

    /// A second account on the instance, `ana`, whose token lists `members`.
    private static func addAna(to harness: ReviewsHarness, members: [RemoteRepoSummary]) -> HostingAccount {
        let ana = HostingAccount(instanceId: ReviewsHarness.instance.id, login: "ana", method: .oauth, status: .ok)
        harness.accounts.append(ana)
        harness.tokenFor[ana.id] = .token("t-ana")
        harness.browser.state { $0.membersByToken["t-ana"] = members }
        return ana
    }

    // MARK: Settings

    @Test("The store starts with the settings saved on disk")
    func loadsConfig() {
        let harness = ReviewsHarness()
        let config = ReviewsConfig(patterns: [Self.pattern("apps/*/android/*")],
                                   manual: [ReviewsHarness.host("team/extra")],
                                   hidden: [ReviewsHarness.host("team/api")],
                                   answeredProposals: ["gitlab.example.test|oss/*"])
        Self.save(config, in: harness)

        let store = harness.makeStore()
        #expect(store.config == config)
    }

    // MARK: Patterns

    @Test("A pattern follows the members it matches, each with its member's clone URL and the account that lists it")
    func patternFollowsMembers() async throws {
        let harness = ReviewsHarness()
        harness.browser.state {
            $0.members = [Self.member("1", "apps/payments/android/payments-app", cloneName: "payments-app"),
                          ReviewsHarness.member("3", "apps/payments/backend/ledger")]
        }
        let ana = Self.addAna(to: harness, members: [Self.member("2", "apps/cards/android/cards-app",
                                                                 cloneName: "cards-app")])
        Self.save(ReviewsConfig(patterns: [Self.pattern("apps/*/android/*")]), in: harness)
        let store = harness.makeStore()
        await store.refresh(force: true)

        #expect(Self.slugs(store) == ["apps/cards/android/cards-app", "apps/payments/android/payments-app"])
        let payments = try #require(Self.repo(store, "apps/payments/android/payments-app"))
        #expect(payments.sources == [.pattern])
        #expect(payments.accountId == harness.account.id)
        #expect(payments.cloneURL == "https://gitlab.example.test/clone/payments-app.git")
        #expect(payments.lastActivity == nil)
        let cards = try #require(Self.repo(store, "apps/cards/android/cards-app"))
        #expect(cards.sources == [.pattern])
        #expect(cards.accountId == ana.id)
        #expect(cards.cloneURL == "https://gitlab.example.test/clone/cards-app.git")
        #expect(Self.reads(harness).sorted() == ["apps/cards/android/cards-app", "apps/payments/android/payments-app"])
    }

    @Test("Offline, a pattern's repos stay with the membership list the day left, also after a relaunch")
    func patternOffline() async {
        let harness = ReviewsHarness()
        harness.browser.state {
            $0.members = [ReviewsHarness.member("1", "apps/payments/android/payments-app"),
                          ReviewsHarness.member("2", "apps/cards/android/cards-app")]
        }
        Self.save(ReviewsConfig(patterns: [Self.pattern("apps/*/android/*")]), in: harness)
        let store = harness.makeStore()
        await store.refresh(force: true)
        let following = ["apps/cards/android/cards-app", "apps/payments/android/payments-app"]
        #expect(Self.slugs(store) == following)

        harness.now = harness.now.addingTimeInterval(25 * 3600)
        harness.browser.state { $0.failure = .network("The Internet connection appears to be offline.") }
        await store.refresh(force: true)
        #expect(Self.listings(harness) == 2)
        #expect(Self.slugs(store) == following)
        #expect(store.repos.allSatisfy { $0.sources == [.pattern] })

        let relaunched = harness.makeStore()
        relaunched.loadSnapshot()
        harness.now = harness.now.addingTimeInterval(60)
        await relaunched.refresh(force: true)
        #expect(Self.slugs(relaunched) == following)
    }

    @Test("Editing a pattern follows what the new one matches; removing it drops the repos only it reached")
    func editAndRemovePattern() async throws {
        let harness = ReviewsHarness()
        // The iOS app is a clone, so a member too.
        harness.locals = [ReviewsHarness.local("apps/payments/ios/payments-app")]
        harness.browser.state {
            $0.members = [ReviewsHarness.member("1", "apps/payments/android/payments-app"),
                          ReviewsHarness.member("2", "apps/cards/android/cards-app")]
        }
        let old = Self.pattern("apps/*/android/*")
        Self.save(ReviewsConfig(patterns: [old]), in: harness)
        let store = harness.makeStore()
        await store.refresh(force: true)
        #expect(Self.slugs(store) == ["apps/cards/android/cards-app", "apps/payments/android/payments-app",
                                      "apps/payments/ios/payments-app"])

        let new = Self.pattern("apps/payments/*/payments-app")
        let outcome = await store.savePattern(new, replacing: old)
        #expect(outcome == .done)
        #expect(store.config.patterns == [new])
        #expect(Self.saved(harness).patterns == [new])
        #expect(Self.slugs(store) == ["apps/payments/android/payments-app", "apps/payments/ios/payments-app"])
        #expect(Self.repo(store, "apps/payments/ios/payments-app")?.sources == [.local, .pattern])
        #expect(Self.listings(harness) == 1)

        await store.removePattern(new)
        #expect(store.config.patterns.isEmpty)
        #expect(Self.saved(harness).patterns.isEmpty)
        #expect(Self.slugs(store) == ["apps/payments/ios/payments-app"])
        #expect(Self.repo(store, "apps/payments/ios/payments-app")?.sources == [.local])
        #expect(Self.listings(harness) == 1)
    }

    // MARK: By hand

    @Test("Following a repo by hand saves it and follows it at once, without reading the membership again")
    func followByHand() async throws {
        let harness = ReviewsHarness.twoRepos()
        harness.provider.state { $0.lists["team/extra"] = [ReviewsHarness.pr(9, by: "octo", updated: 10)] }
        let store = harness.makeStore()
        await store.refresh(force: true)
        #expect(Self.reads(harness).count == 2)

        let outcome = await store.follow(Self.found("team/extra"))
        #expect(outcome == .done)
        #expect(store.config.manual == [ReviewsHarness.host("team/extra")])
        #expect(Self.saved(harness).manual == [ReviewsHarness.host("team/extra")])
        let extra = try #require(Self.repo(store, "team/extra"))
        #expect(extra.sources == [.manual])
        #expect(extra.accountId == harness.account.id)
        #expect(extra.cloneURL == FollowedRepos.cloneURL(for: ReviewsHarness.host("team/extra")))
        #expect(Self.slugs(store) == ["team/api", "team/app", "team/extra"])
        #expect(Self.listings(harness) == 1)
        // Only the new repo is read.
        #expect(Self.reads(harness).count == 3)
        #expect(Self.reads(harness).last == "team/extra")
        #expect(store.pulls[ReviewsHarness.key("team/extra")]?.map(\.number) == [9])
        let snapshot = ReviewsSnapshotStore(directory: harness.directory).load()
        #expect(snapshot?.repos.contains { $0.host.slug == "team/extra" } == true)

        // Following it again, whatever the case, doesn't add it twice.
        let again = await store.follow(Self.found("Team/Extra"))
        #expect(again == .done)
        #expect(store.config.manual.count == 1)
    }

    @Test("Following a hidden repo by hand shows it again")
    func followUnhides() async {
        let harness = ReviewsHarness.twoRepos()
        Self.save(ReviewsConfig(hidden: [ReviewsHarness.host("Team/API")]), in: harness)
        let store = harness.makeStore()
        await store.refresh(force: true)
        #expect(Self.slugs(store) == ["team/app"])

        let outcome = await store.follow(Self.found("team/api"))
        #expect(outcome == .done)
        #expect(store.config.hidden.isEmpty)
        #expect(store.config.manual == [ReviewsHarness.host("team/api")])
        #expect(Self.saved(harness) == store.config)
        #expect(Self.repo(store, "team/api")?.sources == [.activity, .manual])
    }

    @Test("Hiding a repo drops it, with the selection and the filter on it, without reading the membership again")
    func hideAtOnce() async {
        let harness = ReviewsHarness.twoRepos()
        harness.provider.state { $0.lists["team/api"] = [ReviewsHarness.pr(3, by: "octo", updated: 300)] }
        let store = harness.makeStore()
        await store.refresh(force: true)
        let api = ReviewsHarness.key("team/api")
        store.showRepo(api)
        store.selectedID = InboxPull.id(repoKey: api, number: 3)
        #expect(store.repoFilter == api)

        await store.hide(ReviewsHarness.host("team/api"))
        #expect(Self.slugs(store) == ["team/app"])
        #expect(store.selectedID == nil)
        #expect(store.repoFilter == nil)
        #expect(store.pulls[api] == nil)
        #expect(store.config.hidden == [ReviewsHarness.host("team/api")])
        #expect(Self.saved(harness).hidden == [ReviewsHarness.host("team/api")])
        #expect(Self.listings(harness) == 1)
        #expect(Self.reads(harness).count == 2)

        // Hiding it again, whatever the case, changes nothing; a refresh keeps it out.
        await store.hide(ReviewsHarness.host("Team/API"))
        #expect(store.config.hidden.count == 1)
        await store.refresh(force: true)
        #expect(Self.slugs(store) == ["team/app"])
    }

    @Test("Hiding a repo followed by hand drops its manual entry")
    func hideManual() async {
        let harness = ReviewsHarness()
        Self.save(ReviewsConfig(manual: [ReviewsHarness.host("team/extra")]), in: harness)
        let store = harness.makeStore()
        await store.refresh(force: true)
        #expect(Self.repo(store, "team/extra")?.sources == [.manual])

        await store.hide(ReviewsHarness.host("team/extra"))
        #expect(store.config.manual.isEmpty)
        #expect(store.config.hidden == [ReviewsHarness.host("team/extra")])
        #expect(Self.saved(harness) == store.config)
        #expect(store.repos.isEmpty)
    }

    @Test("Showing a hidden repo again brings it back if a source still reaches it")
    func unhide() async {
        let harness = ReviewsHarness.twoRepos()
        harness.provider.state { $0.lists["team/api"] = [ReviewsHarness.pr(3, by: "octo", updated: 300)] }
        Self.save(ReviewsConfig(hidden: [ReviewsHarness.host("team/api"), ReviewsHarness.host("oss/gone")]),
                  in: harness)
        let store = harness.makeStore()
        await store.refresh(force: true)
        #expect(Self.slugs(store) == ["team/app"])

        await store.unhide(ReviewsHarness.host("team/api"))
        #expect(Self.slugs(store) == ["team/api", "team/app"])
        #expect(Self.repo(store, "team/api")?.sources == [.activity])
        #expect(store.pulls[ReviewsHarness.key("team/api")]?.map(\.number) == [3])
        #expect(Self.listings(harness) == 1)

        // No source reaches this one: it stays out.
        await store.unhide(ReviewsHarness.host("oss/gone"))
        #expect(store.config.hidden.isEmpty)
        #expect(Self.saved(harness).hidden.isEmpty)
        #expect(Self.slugs(store) == ["team/api", "team/app"])
    }

    @Test("Unfollowing drops a repo followed only by hand; a cloned one stays as a clone")
    func unfollow() async {
        let harness = ReviewsHarness.twoRepos()
        Self.save(ReviewsConfig(manual: [ReviewsHarness.host("team/extra"), ReviewsHarness.host("team/app")]),
                  in: harness)
        let store = harness.makeStore()
        await store.refresh(force: true)
        #expect(Self.repo(store, "team/extra")?.sources == [.manual])
        #expect(Self.repo(store, "team/app")?.sources == [.local, .manual])

        await store.unfollow(ReviewsHarness.host("team/extra"))
        #expect(Self.repo(store, "team/extra") == nil)
        await store.unfollow(ReviewsHarness.host("team/app"))
        #expect(Self.repo(store, "team/app")?.sources == [.local])
        #expect(store.config.manual.isEmpty)
        #expect(Self.saved(harness).manual.isEmpty)
    }

    // MARK: Limit

    @Test("A pattern or a repo that would pass the limit of 100 isn't followed, and the settings don't change")
    func overLimit() async {
        let harness = ReviewsHarness()
        harness.locals = (0..<99).map { ReviewsHarness.local("org/repo-\($0)") }
        harness.browser.state {
            $0.members = ["a", "b", "c"].map { ReviewsHarness.member($0, "apps/\($0)/android/app") }
        }
        let store = harness.makeStore()
        await store.refresh(force: true)
        #expect(store.repos.count == 99)

        let wide = await store.savePattern(Self.pattern("apps/*/android/*"), replacing: nil)
        #expect(wide == .overLimit(total: 102))
        #expect(store.config == ReviewsConfig())
        #expect(Self.saved(harness) == ReviewsConfig())
        #expect(store.repos.count == 99)

        let narrow = await store.savePattern(Self.pattern("apps/a/android/*"), replacing: nil)
        #expect(narrow == .done)
        #expect(store.repos.count == 100)
        #expect(store.droppedByLimit == 0)

        let manual = await store.follow(Self.found("team/extra"))
        #expect(manual == .overLimit(total: 101))
        #expect(store.config.manual.isEmpty)
        #expect(Self.saved(harness).manual.isEmpty)
        #expect(Self.repo(store, "team/extra") == nil)
        #expect(!Self.reads(harness).contains("team/extra"))
    }

    @Test("Over the limit, a change that keeps or lowers the total goes through; one that raises it doesn't")
    func overLimitNarrowing() async {
        let harness = ReviewsHarness()
        let busy = (0..<101).map { "org/repo-\($0)" }
        let android = ["a", "b", "c"].map { "apps/\($0)/android/app" }
        harness.browser.state {
            $0.members = (busy + android).enumerated().map { ReviewsHarness.member("m\($0.offset)", $0.element) }
        }
        // Activity alone gives 101 repos; the pattern adds three more.
        harness.activity.state {
            $0.hits = busy.indices.map {
                ActivityHit(ref: .projectId("m\($0)"), at: ReviewsHarness.date(1_789_000_000))
            }
        }
        let wide = Self.pattern("apps/*/android/*")
        Self.save(ReviewsConfig(patterns: [wide]), in: harness)
        let store = harness.makeStore()
        await store.refresh(force: true)
        #expect(store.repos.count + store.droppedByLimit == 104)

        let narrow = Self.pattern("apps/a/android/*")
        let narrowing = await store.savePattern(narrow, replacing: wide)
        #expect(narrowing == .done)
        #expect(store.config.patterns == [narrow])
        #expect(Self.saved(harness).patterns == [narrow])
        #expect(store.repos.count + store.droppedByLimit == 102)

        // Following by hand a repo the activity follows already keeps the total.
        let followed = await store.follow(Self.found("org/repo-0"))
        #expect(followed == .done)
        #expect(store.config.manual == [ReviewsHarness.host("org/repo-0")])
        #expect(store.repos.count + store.droppedByLimit == 102)

        let widening = await store.savePattern(wide, replacing: narrow)
        #expect(widening == .overLimit(total: 104))
        #expect(store.config.patterns == [narrow])
        #expect(Self.saved(harness).patterns == [narrow])
        #expect(store.repos.count + store.droppedByLimit == 102)
    }

    @Test("A total passes the limit when it's over 100 and above what the inbox follows now")
    func exceedsLimit() async {
        let under = ReviewsHarness()
        under.locals = (0..<99).map { ReviewsHarness.local("org/repo-\($0)") }
        let store = under.makeStore()
        await store.refresh(force: true)
        #expect(!store.exceedsLimit(100))
        #expect(store.exceedsLimit(101))

        let over = ReviewsHarness()
        over.locals = (0..<101).map { ReviewsHarness.local("org/repo-\($0)") }
        let busy = over.makeStore()
        await busy.refresh(force: true)
        #expect(busy.repos.count + busy.droppedByLimit == 101)
        #expect(!busy.exceedsLimit(100))
        #expect(!busy.exceedsLimit(101))
        #expect(busy.exceedsLimit(102))
    }

    // MARK: Proposal

    /// Activity in three Android apps under `apps/`, and `extra` more Android
    /// apps the account belongs to, plus oss/lib.
    private static func proposalHarness(extra: Int = 1) -> ReviewsHarness {
        let harness = ReviewsHarness()
        let base = ["apps/payments/android/payments-app", "apps/cards/android/cards-app",
                    "apps/loans/android/loans-app"]
        let extras = (0..<extra).map { "apps/extra-\($0)/android/extra-\($0)-app" }
        harness.browser.state {
            $0.members = (base + extras + ["oss/lib"]).enumerated().map {
                ReviewsHarness.member("p\($0.offset)", $0.element)
            }
        }
        harness.activity.state {
            $0.hits = (0..<3).map {
                ActivityHit(ref: .projectId("p\($0)"), at: ReviewsHarness.date(1_789_000_000 + Double($0)))
            }
        }
        return harness
    }

    @Test("A pattern is proposed from the repos followed; Not now keeps it away, Follow applies it")
    func proposal() async throws {
        let harness = Self.proposalHarness()
        let store = harness.makeStore()
        await store.refresh(force: true)

        let proposal = try #require(store.proposal)
        #expect(proposal.pattern.text == "apps/*/android/*")
        #expect(proposal.adds == 1)
        #expect(proposal.total == 4)
        #expect(store.repos.count == 3)

        store.dismissProposal()
        #expect(store.proposal == nil)
        #expect(store.config.answeredProposals == [proposal.pattern.id])
        #expect(Self.saved(harness).answeredProposals == [proposal.pattern.id])
        await store.refresh(force: true)
        #expect(store.proposal == nil)

        let other = Self.proposalHarness()
        let accepting = other.makeStore()
        await accepting.refresh(force: true)
        #expect(accepting.proposal == proposal)
        let outcome = await accepting.acceptProposal()
        #expect(outcome == .done)
        #expect(accepting.config.patterns == [proposal.pattern])
        #expect(accepting.config.answeredProposals == [proposal.pattern.id])
        #expect(Self.saved(other) == accepting.config)
        #expect(Self.repo(accepting, "apps/extra-0/android/extra-0-app")?.sources == [.pattern])
        #expect(accepting.repos.count == 4)
        #expect(accepting.proposal == nil)
        #expect(Self.reads(other).contains("apps/extra-0/android/extra-0-app"))
    }

    @Test("A proposal that would pass the limit can't be accepted, and nothing changes")
    func proposalOverLimit() async throws {
        let harness = Self.proposalHarness(extra: 98)
        let store = harness.makeStore()
        await store.refresh(force: true)
        let proposal = try #require(store.proposal)
        #expect(proposal.adds == 98)
        #expect(proposal.total == 101)

        let outcome = await store.acceptProposal()
        #expect(outcome == .overLimit(total: 101))
        #expect(store.config == ReviewsConfig())
        #expect(Self.saved(harness) == ReviewsConfig())
        #expect(store.proposal == proposal)
        #expect(store.repos.count == 3)
    }

    @Test("What a pattern would add and the repos followed with it, replacing another, change nothing")
    func patternCount() async {
        let harness = Self.proposalHarness(extra: 2)
        let store = harness.makeStore()
        await store.refresh(force: true)

        let count = store.patternCount(Self.pattern("apps/*/android/*"), replacing: nil)
        #expect(count.adds == 2)
        #expect(count.total == 5)
        let one = store.patternCount(Self.pattern("apps/extra-0/android/*"), replacing: nil)
        #expect(one.adds == 1)
        #expect(one.total == 4)
        #expect(store.config == ReviewsConfig())
        #expect(store.repos.count == 3)
    }

    /// Over the limit: three Android apps with the newest activity, 100
    /// repos under `org/` after them and a fourth Android app, the oldest,
    /// all followed by activity; 104 in all, so the limit leaves out the
    /// fourth app and three of the `org/` repos. oss/lib is a member nobody
    /// follows.
    private static func overLimitHarness() -> ReviewsHarness {
        let harness = ReviewsHarness()
        let android = ["a", "b", "c"].map { "apps/\($0)/android/app" }
        let busy = (0..<100).map { "org/repo-\($0)" }
        harness.browser.state {
            $0.members = android.enumerated().map { ReviewsHarness.member("b\($0.offset)", $0.element) }
                + busy.enumerated().map { ReviewsHarness.member("m\($0.offset)", $0.element) }
                + [ReviewsHarness.member("late", "apps/d/android/app"), ReviewsHarness.member("lib", "oss/lib")]
        }
        harness.activity.state {
            $0.hits = android.indices.map { ActivityHit(ref: .projectId("b\($0)"), at: ReviewsHarness.date(1_789_000_100)) }
                + busy.indices.map { ActivityHit(ref: .projectId("m\($0)"), at: ReviewsHarness.date(1_789_000_000)) }
                + [ActivityHit(ref: .projectId("late"), at: ReviewsHarness.date(1_788_000_000))]
        }
        return harness
    }

    @Test("Over the limit, no pattern is proposed whose only additions are repos the limit leaves out")
    func noProposalOfDroppedRepos() async {
        let harness = Self.overLimitHarness()
        let store = harness.makeStore()
        await store.refresh(force: true)
        #expect(store.repos.count == 100)
        #expect(store.droppedByLimit == 4)
        #expect(!store.repos.contains { $0.host.slug == "apps/d/android/app" })

        #expect(store.proposal == nil)
        #expect(store.patternCount(Self.pattern("apps/*/android/*"), replacing: nil).adds == 0)
        #expect(store.patternCount(Self.pattern("org/*"), replacing: nil).adds == 0)
    }

    @Test("The repos to follow leave out those the limit drops: they're followed already")
    func followableSkipsDroppedRepos() async {
        let harness = Self.overLimitHarness()
        let store = harness.makeStore()
        await store.refresh(force: true)
        #expect(store.droppedByLimit == 4)

        #expect(store.followableRepos.map(\.host.slug) == ["oss/lib"])
    }

    @Test("With accounts on two instances, the proposal is the first instance's in the order of the accounts")
    func proposalOrderAcrossInstances() async throws {
        /// Three repos of the same shape followed by activity and a fourth
        /// one not followed, on each instance: `apps/*/android/*` on the
        /// GitLab instance, `octo/*` on github.com.
        func harness(gitHubFirst: Bool) -> ReviewsHarness {
            let harness = ReviewsHarness()
            let octo = HostingAccount(instanceId: HostingInstance.gitHubDotCom.id, login: "octo", method: .oauth,
                                      status: .ok)
            harness.accounts = gitHubFirst ? [octo, harness.account] : [harness.account, octo]
            harness.tokenFor[octo.id] = .token("t-octo")
            harness.browser.state {
                $0.members = ["a", "b", "c", "d"].enumerated().map {
                    ReviewsHarness.member("gl\($0.offset)", "apps/\($0.element)/android/\($0.element)-app")
                }
                $0.membersByToken["t-octo"] = ["a", "b", "c", "d"].enumerated().map {
                    ReviewsHarness.member("gh\($0.offset)", "octo/app-\($0.element)")
                }
            }
            harness.activity.state {
                $0.hits = (0..<3).flatMap {
                    [ActivityHit(ref: .projectId("gl\($0)"), at: ReviewsHarness.date(1_789_000_000)),
                     ActivityHit(ref: .projectId("gh\($0)"), at: ReviewsHarness.date(1_789_000_000))]
                }
            }
            return harness
        }

        let gitLabFirst = harness(gitHubFirst: false).makeStore()
        await gitLabFirst.refresh(force: true)
        #expect(gitLabFirst.repos.count == 6)
        let fromGitLab = try #require(gitLabFirst.proposal)
        #expect(fromGitLab.pattern.host == ReviewsHarness.instance.host)
        #expect(fromGitLab.pattern.text == "apps/*/android/*")
        #expect(fromGitLab.adds == 1)

        let gitHubFirst = harness(gitHubFirst: true).makeStore()
        await gitHubFirst.refresh(force: true)
        let fromGitHub = try #require(gitHubFirst.proposal)
        #expect(fromGitHub.pattern.host == HostingInstance.gitHubDotCom.host)
        #expect(fromGitHub.pattern.text == "octo/*")
        #expect(fromGitHub.adds == 1)
    }

    @Test("What a pattern would add is counted on the accounts of the last refresh, as the proposal is")
    func patternCountUsesTheRoundsAccounts() async throws {
        let harness = Self.proposalHarness()
        // Ana belongs to two more Android apps.
        _ = Self.addAna(to: harness, members: [ReviewsHarness.member("a1", "apps/maps/android/maps-app"),
                                               ReviewsHarness.member("a2", "apps/notes/android/notes-app")])
        let store = harness.makeStore()
        await store.refresh(force: true)
        let proposal = try #require(store.proposal)
        #expect(proposal.adds == 3)

        // Ana is removed; no refresh has run since.
        harness.accounts.removeLast()
        let count = store.patternCount(proposal.pattern, replacing: nil)
        #expect(count.adds == proposal.adds)
        #expect(count.total == proposal.total)
    }

    @Test("Without accounts the proposal goes")
    func proposalClearedWithoutAccounts() async {
        let harness = Self.proposalHarness()
        let store = harness.makeStore()
        await store.refresh(force: true)
        #expect(store.proposal != nil)

        harness.accounts = []
        await store.refresh(force: true)
        #expect(store.proposal == nil)
    }

    // MARK: Before the first refresh

    @Test("Before the first refresh, a change reads the inbox first")
    func beforeFirstRefresh() async {
        let harness = ReviewsHarness.twoRepos()
        let store = harness.makeStore()
        let outcome = await store.follow(Self.found("team/extra"))
        #expect(outcome == .done)
        #expect(Self.listings(harness) == 1)
        #expect(Self.slugs(store) == ["team/api", "team/app", "team/extra"])
        #expect(Self.repo(store, "team/extra")?.sources == [.manual])
        #expect(Self.reads(harness).filter { $0 == "team/extra" }.count == 1)

        let hiding = ReviewsHarness.twoRepos()
        let hidingStore = hiding.makeStore()
        await hidingStore.hide(ReviewsHarness.host("team/api"))
        #expect(Self.listings(hiding) == 1)
        #expect(Self.slugs(hidingStore) == ["team/app"])
        #expect(Self.saved(hiding).hidden == [ReviewsHarness.host("team/api")])

        // The limit is checked on the round that refresh read.
        let full = ReviewsHarness()
        full.locals = (0..<100).map { ReviewsHarness.local("org/repo-\($0)") }
        let fullStore = full.makeStore()
        let over = await fullStore.follow(Self.found("team/extra"))
        #expect(over == .overLimit(total: 101))
        #expect(Self.listings(full) == 1)
        #expect(fullStore.config == ReviewsConfig())
        #expect(fullStore.repos.count == 100)
    }

    // MARK: Renames

    @Test("A renamed clone whose old path is followed by hand keeps that path and isn't looked up")
    func manualKeepsRenamedClone() async throws {
        let harness = ReviewsHarness()
        harness.clonesAreMembers = false
        harness.locals = [ReviewsHarness.local("team/old-name")]
        harness.browser.state { $0.members = [ReviewsHarness.member("m0", "team/new-name")] }
        harness.search.state { $0.paths["team/old-name"] = "team/new-name" }
        Self.save(ReviewsConfig(manual: [ReviewsHarness.host("team/old-name")]), in: harness)
        let store = harness.makeStore()
        await store.refresh(force: true)

        #expect(store.repos.map(\.host.slug) == ["team/old-name"])
        let repo = try #require(store.repos.first)
        #expect(repo.sources == [.local, .manual])
        #expect(repo.outdatedOrigin == nil)
        #expect(harness.search.state { $0.lookups } == 0)
    }

    // MARK: Followable

    @Test("The repos to follow are every account's members not followed nor hidden, once each, by path")
    func followable() async {
        let harness = ReviewsHarness()
        harness.locals = [ReviewsHarness.local("team/app")]
        harness.browser.state {
            $0.members = [ReviewsHarness.member("1", "team/zeta"), ReviewsHarness.member("2", "team/api"),
                          ReviewsHarness.member("5", "Team/Hidden"), ReviewsHarness.member("6", "Team/Beta")]
        }
        _ = Self.addAna(to: harness, members: [ReviewsHarness.member("3", "oss/lib"),
                                               ReviewsHarness.member("4", "team/api")])
        Self.save(ReviewsConfig(hidden: [ReviewsHarness.host("team/hidden")]), in: harness)
        let store = harness.makeStore()
        await store.refresh(force: true)

        let followable = store.followableRepos
        #expect(followable.map(\.host.slug) == ["oss/lib", "team/api", "Team/Beta", "team/zeta"])
        #expect(followable.allSatisfy { $0.instanceId == ReviewsHarness.instance.id })
        #expect(followable.first?.cloneURL == "https://gitlab.example.test/oss/lib.git")
    }
}
