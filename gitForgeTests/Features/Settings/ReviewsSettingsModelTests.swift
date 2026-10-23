import Foundation
import Testing
@testable import gitForge

@Suite("ReviewsSettingsModel")
@MainActor
struct ReviewsSettingsModelTests {
    nonisolated static let gitLab = "gitlab.example.test"
    nonisolated static let gitHub = "github.com"
    nonisolated static let account = UUID(uuidString: "00000000-0000-0000-0000-00000000C001")!

    /// `path` on `host`: the last segment is the repo, the rest its owner.
    private func remote(_ path: String, on host: String = gitLab) -> RemoteHost {
        let segments = path.split(separator: "/").map(String.init)
        return RemoteHost(provider: host == Self.gitHub ? .github : .gitlab, host: host,
                          owner: segments.dropLast().joined(separator: "/"), repo: segments.last!)
    }

    private func repo(_ path: String, on host: String = gitLab, sources: Set<FollowSource> = [.activity]) -> ReviewRepo {
        ReviewRepo(host: remote(path, on: host), accountId: Self.account, sources: sources, lastActivity: nil,
                   cloneURL: "https://\(host)/\(path).git")
    }

    private func found(_ path: String, on host: String = gitLab) -> FoundRepo {
        FoundRepo(host: remote(path, on: host), instanceId: Self.account, cloneURL: "https://\(host)/\(path).git")
    }

    @Test("A repo's sources read In gitForge, Activity, Pattern, Manual, whatever the set's order")
    func sourceTitlesInOrder() {
        let all = repo("apps/payments/android/payments-app", sources: [.manual, .pattern, .local, .activity])
        #expect(ReviewsSettingsModel.sourceTitles(all.sources) == ["In gitForge", "Activity", "Pattern", "Manual"])
        #expect(ReviewsSettingsModel.sourceTitles([.manual, .local]) == ["In gitForge", "Manual"])
        #expect(ReviewsSettingsModel.sourceOrder.map(\.title) == ["In gitForge", "Activity", "Pattern", "Manual"])
    }

    @Test("Followed repos group by host alphabetically, each host's by path ignoring case, numbers by value")
    func groupsByHost() {
        let repos = [
            repo("apps/payments/backend/ledger"),
            repo("octo/zeta", on: Self.gitHub),
            repo("Apps/payments/android/payments-app"),
            repo("oss/lib", on: Self.gitHub),
            repo("apps/platform/release-tools"),
            repo("Octo-Org/design-tokens", on: Self.gitHub),
            repo("apps/archive/service-10"),
            repo("apps/archive/service-2"),
        ]
        let groups = ReviewsSettingsModel.groups(repos)
        #expect(groups.map(\.host) == [Self.gitHub, Self.gitLab])
        #expect(groups[0].repos.map(\.host.slug) == ["Octo-Org/design-tokens", "octo/zeta", "oss/lib"])
        #expect(groups[1].repos.map(\.host.slug)
            == ["apps/archive/service-2", "apps/archive/service-10", "Apps/payments/android/payments-app",
                "apps/payments/backend/ledger", "apps/platform/release-tools"])
        #expect(ReviewsSettingsModel.groups([ReviewRepo]()).isEmpty)

        // The repos to add, the same way.
        let toAdd = ReviewsSettingsModel.groups([found("oss/lib", on: Self.gitHub), found("apps/x/web"),
                                                 found("Octo/dotfiles", on: Self.gitHub)])
        #expect(toAdd.map(\.host) == [Self.gitHub, Self.gitLab])
        #expect(toAdd[0].repos.map(\.host.slug) == ["Octo/dotfiles", "oss/lib"])
    }

    @Test("Stop following only a repo followed by hand alone; any other source means Hide")
    func removal() {
        #expect(ReviewsSettingsModel.removal(for: repo("oss/lib", on: Self.gitHub, sources: [.manual])) == .stopFollowing)
        #expect(ReviewsSettingsModel.removal(for: repo("oss/lib", on: Self.gitHub, sources: [.local, .manual])) == .hide)
        #expect(ReviewsSettingsModel.removal(for: repo("apps/catalog/android/catalog-app", sources: [.pattern])) == .hide)
        #expect(ReviewsSettingsModel.removal(for: repo("apps/payments/backend/ledger", sources: [.activity])) == .hide)
    }

    @Test("Add repository filters by path: each word unbroken, ignoring case and accents, in the list's order")
    func filterByWords() {
        let repos = [found("apps/payments/android/payments-app"), found("apps/payments/backend/ledger"),
                     found("oss/lib", on: Self.gitHub)]
        let paths: (String) -> [String] = { query in
            ReviewsSettingsModel.filter(repos, query: query).map(\.host.slug)
        }
        #expect(paths("") == repos.map(\.host.slug))
        #expect(paths("   ") == repos.map(\.host.slug))
        #expect(paths("payments") == ["apps/payments/android/payments-app", "apps/payments/backend/ledger"])
        #expect(paths("app pay") == ["apps/payments/android/payments-app", "apps/payments/backend/ledger"])
        #expect(paths("  andro  PAYMENTS-app ") == ["apps/payments/android/payments-app"])
        #expect(paths("LÉDGER") == ["apps/payments/backend/ledger"])
        // Letters spread apart don't count: "pmts" is in payments, but not unbroken.
        #expect(paths("pmts").isEmpty)
        // Every word has to be there.
        #expect(paths("payments lib").isEmpty)
    }

    @Test("Hidden repos by host alphabetically, then by path ignoring case, numbers by value")
    func hiddenOrder() {
        let hidden = [remote("apps/sandbox/playground-10"), remote("octo/notes", on: Self.gitHub),
                      remote("Apps/payments/backend/ledger-sandbox"), remote("apps/sandbox/playground-9")]
        #expect(ReviewsSettingsModel.sortedHidden(hidden).map(\.slug)
            == ["octo/notes", "Apps/payments/backend/ledger-sandbox", "apps/sandbox/playground-9",
                "apps/sandbox/playground-10"])
    }

    @Test("A pattern's count is the followed repos it matches")
    func patternRepoCount() throws {
        let pattern = try #require(FollowPattern(host: Self.gitLab, text: "apps/*/android/*"))
        let repos = [repo("apps/payments/android/payments-app", sources: [.local, .pattern]),
                     repo("Apps/Loyalty/Android/loyalty-app", sources: [.pattern]),
                     repo("apps/payments/backend/ledger"),
                     repo("apps/x/android/y", on: Self.gitHub)]
        #expect(ReviewsSettingsModel.repoCount(of: pattern, in: repos) == 2)
    }
}
