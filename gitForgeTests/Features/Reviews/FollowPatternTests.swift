import Foundation
import Testing
@testable import gitForge

@Suite("Follow patterns")
struct FollowPatternTests {
    static let gitlab = HostingInstance(kind: .gitlab, host: "gitlab.example.test")
    static let code = HostingInstance(kind: .gitlab, host: "code.example.test")
    static let host = "gitlab.example.test"

    static func repo(_ path: String, on instance: HostingInstance = gitlab) -> RemoteHost {
        RemoteHost.make(fullName: path, on: instance)!
    }
    static func repos(_ paths: [String], on instance: HostingInstance = gitlab) -> [RemoteHost] {
        paths.map { repo($0, on: instance) }
    }
    static func keys(_ repos: [RemoteHost]) -> Set<String> { Set(repos.map(FollowedRepos.key)) }
    static func pattern(_ text: String) -> FollowPattern { FollowPattern(host: host, text: text)! }

    // MARK: Parsing and matching

    @Test("A valid pattern is trimmed and matches the same path, any case, on its own host only")
    func valid() throws {
        let pattern = try #require(FollowPattern(host: Self.host, text: " Apps/*/Android/* "))
        #expect(pattern.text == "Apps/*/Android/*")
        #expect(pattern.host == Self.host)
        #expect(pattern.matches(Self.repo("apps/payments/android/payments-app")))
        #expect(pattern.matches(Self.repo("APPS/Payments/ANDROID/Payments-App")))
        #expect(!pattern.matches(Self.repo("apps/payments/ios/payments-app")))
        #expect(!pattern.matches(Self.repo("apps/payments/android/sub/payments-app")))
        #expect(!pattern.matches(Self.repo("apps/android/payments-app")))
        #expect(!pattern.matches(Self.repo("apps/payments/android/payments-app", on: Self.code)))
    }

    @Test("Whitespace and newlines around the text don't count")
    func trimmed() throws {
        let pattern = try #require(FollowPattern(host: Self.host, text: "\n\t octo/* \n"))
        #expect(pattern.text == "octo/*")
        #expect(pattern.matches(Self.repo("octo/tools")))
    }

    @Test("A star is exactly one segment, so a longer or shorter path doesn't match", arguments: [
        ("octo/*", "octo/tools", true),
        ("octo/*", "octo/team/tools", false),
        ("*/tools", "octo/tools", true),
        ("*/tools", "marta/Tools", true),
        ("*/tools", "marta/lib", false),
        ("team/*/*", "team/sub/tools", true),
        ("team/*/*", "team/tools", false),
    ])
    func oneSegmentPerStar(text: String, path: String, expected: Bool) {
        #expect(Self.pattern(text).matches(Self.repo(path)) == expected)
    }

    @Test("Invalid patterns are refused", arguments: [
        "", "   ", "*", "*/*", "*/*/*", "apps", "apps/payments", "apps//*", "apps/*/", "/apps/*",
        "apps/pay*", "apps/*pay", "apps/**", "apps/*/a*b",
    ])
    func invalid(text: String) {
        #expect(FollowPattern(host: Self.host, text: text) == nil)
    }

    @Test("Two spellings that differ only in case have the same id")
    func sameId() throws {
        let first = try #require(FollowPattern(host: Self.host, text: "apps/*/android/*"))
        let second = try #require(FollowPattern(host: Self.host, text: "APPS/*/Android/*"))
        #expect(first.id == second.id)
        #expect(first.id == "gitlab.example.test|apps/*/android/*")
        // The same text on another instance is another pattern.
        #expect(FollowPattern(host: "code.example.test", text: "apps/*/android/*")?.id != first.id)
    }

    @Test("A pattern survives the round trip through JSON")
    func codable() throws {
        let pattern = Self.pattern("Apps/*/Android/*")
        let data = try JSONEncoder().encode(pattern)
        let decoded = try JSONDecoder().decode(FollowPattern.self, from: data)
        #expect(decoded == pattern)
        #expect(decoded.text == "Apps/*/Android/*")
    }

    // MARK: Inference

    @Test("Three android apps under apps/ give apps/*/android/*, not the one ios app")
    func family() {
        let base = Self.repos(["apps/payments/android/payments-app", "apps/ledger/android/ledger-app",
                               "apps/cards/android/cards-app", "apps/payments/ios/payments-ios"])
        let members = base + Self.repos(["apps/loans/android/loans-app", "apps/loans/ios/loans-ios"])
        let proposal = PatternInference.propose(base: base, members: members, following: Self.keys(base),
                                                excluding: [])
        #expect(proposal?.text == "apps/*/android/*")
        #expect(proposal?.host == Self.host)
    }

    @Test("Fewer than three repos in the base propose nothing")
    func tooFewBase() {
        let base = Self.repos(["octo/a", "octo/b"])
        let members = base + Self.repos(["octo/c", "octo/d"])
        #expect(PatternInference.minimumBase == 3)
        #expect(PatternInference.propose(base: base, members: members, following: Self.keys(base),
                                         excluding: []) == nil)
    }

    @Test("A pattern of only stars is never proposed")
    func allStarsRefused() {
        let github = HostingInstance.gitHubDotCom
        let base = Self.repos(["octo/app", "marta/lib", "ana/tools"], on: github)
        let members = base + Self.repos(["octo/extra", "marta/extra"], on: github)
        #expect(PatternInference.propose(base: base, members: members, following: Self.keys(base),
                                         excluding: []) == nil)
    }

    @Test("Three repos of one owner give owner/*")
    func orgPattern() {
        let github = HostingInstance.gitHubDotCom
        let base = Self.repos(["octo/a", "octo/b", "octo/c"], on: github)
        let members = base + Self.repos(["octo/d"], on: github)
        let proposal = PatternInference.propose(base: base, members: members, following: Self.keys(base),
                                                excluding: [])
        #expect(proposal?.text == "octo/*")
        #expect(proposal?.host == "github.com")
    }

    @Test("A GitLab owner with several segments is read as separate segments")
    func nestedGroup() {
        let base = Self.repos(["team/sub/a", "team/sub/b", "team/sub/c"])
        let members = base + Self.repos(["team/sub/d"])
        let proposal = PatternInference.propose(base: base, members: members, following: Self.keys(base),
                                                excluding: [])
        #expect(proposal?.text == "team/sub/*")
    }

    @Test("With nothing new for the pattern to add, nothing is proposed")
    func nothingToAdd() {
        let base = Self.repos(["octo/a", "octo/b", "octo/c"])
        let extra = Self.repos(["octo/d"])
        // The only repo left is already followed or hidden.
        #expect(PatternInference.propose(base: base, members: base + extra,
                                         following: Self.keys(base + extra), excluding: []) == nil)
        // Members the pattern doesn't match don't count as something to add.
        #expect(PatternInference.propose(base: base, members: base + Self.repos(["marta/d"]),
                                         following: Self.keys(base), excluding: []) == nil)
        // Without the membership list there is nothing to propose.
        #expect(PatternInference.propose(base: base, members: [], following: Self.keys(base),
                                         excluding: []) == nil)
        // Control: the same base with a repo to add does get a proposal.
        #expect(PatternInference.propose(base: base, members: base + extra, following: Self.keys(base),
                                         excluding: [])?.text == "octo/*")
    }

    @Test("A star needs at least two different values")
    func starNeedsTwoValues() {
        // apps/pay/*/* would add apps/pay/z/d, but the base never varies at the third segment.
        let base = Self.repos(["apps/pay/x/a", "apps/pay/x/b", "apps/pay/x/c"])
        let members = base + Self.repos(["apps/pay/z/d"])
        #expect(PatternInference.propose(base: base, members: members, following: Self.keys(base),
                                         excluding: []) == nil)
    }

    @Test("The next best pattern comes up once the best is excluded")
    func excludedNextBest() {
        let base = Self.repos(["apps/payments/android/payments-app", "apps/ledger/android/ledger-app",
                               "apps/cards/android/cards-app", "apps/payments/ios/payments-ios",
                               "apps/ledger/ios/ledger-ios", "apps/cards/ios/cards-ios"])
        let members = base + Self.repos(["apps/loans/android/loans-app", "apps/loans/ios/loans-ios"])
        let following = Self.keys(base)

        let best = PatternInference.propose(base: base, members: members, following: following, excluding: [])
        #expect(best?.text == "apps/*/android/*")

        let next = PatternInference.propose(base: base, members: members, following: following,
                                            excluding: [Self.pattern("apps/*/android/*").id])
        #expect(next?.text == "apps/*/ios/*")

        let none = PatternInference.propose(base: base, members: members, following: following,
                                            excluding: [Self.pattern("apps/*/android/*").id,
                                                        Self.pattern("apps/*/ios/*").id])
        #expect(none == nil)
    }

    @Test("The pattern covering more of the base wins, even with more stars")
    func coverageWins() {
        // octo/* has one star and sorts first, but zeta/*/android/* covers four repos to its three.
        let base = Self.repos(["octo/a", "octo/b", "octo/c", "zeta/p/android/p1", "zeta/q/android/q1",
                               "zeta/r/android/r1", "zeta/s/android/s1"])
        let members = base + Self.repos(["octo/d", "zeta/t/android/t1"])
        let proposal = PatternInference.propose(base: base, members: members, following: Self.keys(base),
                                                excluding: [])
        #expect(proposal?.text == "zeta/*/android/*")
    }

    @Test("With the same coverage, the pattern with fewer stars wins")
    func fewerStarsWin() {
        // Both cover three repos and apps/*/android/* sorts first, but it has two stars.
        let base = Self.repos(["octo/a", "octo/b", "octo/c", "apps/p/android/p1", "apps/q/android/q1",
                               "apps/r/android/r1"])
        let members = base + Self.repos(["octo/d", "apps/s/android/s1"])
        let proposal = PatternInference.propose(base: base, members: members, following: Self.keys(base),
                                                excluding: [])
        #expect(proposal?.text == "octo/*")
    }

    @Test("The literals keep the case of the first repo by key")
    func firstByKeyKeepsCase() {
        let base = Self.repos(["Apps/payments/Android/payments-app", "apps/ledger/android/ledger-app",
                               "APPS/cards/ANDROID/cards-app"])
        let members = base + Self.repos(["apps/loans/android/loans-app"])
        let proposal = PatternInference.propose(base: base, members: members, following: Self.keys(base),
                                                excluding: [])
        // The keys sort apps/cards/... first, and that repo is written APPS/cards/ANDROID/....
        #expect(proposal?.text == "APPS/*/ANDROID/*")
        // Any spelling matches the same repos and has the same id.
        #expect(proposal?.id == Self.pattern("apps/*/android/*").id)
        #expect(proposal.map { base.allSatisfy($0.matches) } == true)
    }

    @Test("Repos listed twice in the base count once")
    func duplicatesCountOnce() {
        let base = Self.repos(["octo/a", "octo/a", "Octo/A", "octo/b"])
        let members = base + Self.repos(["octo/c"])
        #expect(PatternInference.propose(base: base, members: members, following: Self.keys(base),
                                         excluding: []) == nil)
    }
}
