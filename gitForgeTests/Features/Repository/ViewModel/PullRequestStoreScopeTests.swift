import Foundation
import Testing
@testable import gitForge

/// Scripted provider: fixed lists, user and checks, and a call log.
private final class FakeProvider: PullRequestProvider, @unchecked Sendable {
    var open: [PullRequest] = []
    var closed: [PullRequest] = []
    var user = "me"
    var checksBySha: [String: [CICheck]] = [:]
    /// What reading the open list throws, while set.
    var openFailure: PullRequestFetchError?
    /// What reading the closed list throws, while set.
    var closedFailure: PullRequestFetchError?
    private(set) var openFetches = 0
    private(set) var closedFetches = 0

    func fetchPulls(host: RemoteHost, state: PullListState, token: String) async throws -> [PullRequest] {
        if state == .closed {
            closedFetches += 1
            if let closedFailure { throw closedFailure }
            return closed
        }
        openFetches += 1
        if let openFailure { throw openFailure }
        return open
    }
    func fetchCurrentUser(host: RemoteHost, token: String) async throws -> String { user }
    func fetchChecks(host: RemoteHost, pull: PullRequest, token: String) async throws -> [CICheck] {
        checksBySha[pull.headSha ?? ""] ?? []
    }
    private(set) var commitCheckTokens: [String] = []
    func fetchCommitChecks(host: RemoteHost, sha: String, token: String) async throws -> [CICheck] {
        commitCheckTokens.append(token)
        return checksBySha[sha] ?? []
    }
    func fetchDetail(host: RemoteHost, number: Int, token: String) async throws -> PullRequestDetail {
        PullRequestDetail(pull: open[0], descriptionMarkdown: nil, labels: [], reviewers: [], assignees: [], mergeable: true, ciStatus: nil)
    }
    func fetchCommits(host: RemoteHost, number: Int, token: String) async throws -> [PullRequestCommit] { [] }
    func fetchFiles(host: RemoteHost, number: Int, token: String) async throws -> [PullRequestFileChange] { [] }
}

@Suite("PullRequestStore — scopes, list CI and checks", .serialized)
@MainActor
struct PullRequestStoreScopeTests {

    private static func pr(_ number: Int, author: String, sha: String) -> PullRequest {
        PullRequest(id: "\(number)", number: number, title: "PR \(number)", state: .open,
                    authorLogin: author, authorAvatarURL: nil, sourceBranch: "f/\(number)", targetBranch: "main",
                    webURL: nil, createdAt: nil, updatedAt: nil, headSha: sha)
    }

    private static func check(_ state: CICheck.State) -> CICheck {
        CICheck(name: "c", context: nil, state: state, duration: nil, failureMessage: nil, webURL: nil)
    }

    private static func makeStore(_ provider: FakeProvider) -> PullRequestStore {
        let host = RemoteHost(provider: .github, host: "github.com", owner: "o", repo: "r")
        return PullRequestStore(
            cli: GitCLI(workingDirectory: URL(fileURLWithPath: "/var/empty")),
            auth: { _, _ in .token("token") },
            resolveHost: { host },
            makeProvider: { _ in provider }
        )
    }

    /// The CI fill runs in a background task; give it a moment.
    private static func settle(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<100 where !condition() { try? await Task.sleep(for: .milliseconds(10)) }
    }

    @Test("Closed is fetched the first time it's shown, and only then")
    func closedLazily() async {
        let provider = FakeProvider()
        provider.open = [Self.pr(1, author: "me", sha: "a")]
        provider.closed = [Self.pr(9, author: "lucia", sha: "z")]
        let store = Self.makeStore(provider)
        await store.load(force: true)
        #expect(provider.closedFetches == 0)
        #expect(store.count(for: .closed) == nil)
        await store.setScope(.closed)
        await store.setScope(.open)
        await store.setScope(.closed)
        #expect(provider.closedFetches == 1)
        #expect(store.visibleItems.map(\.number) == [9])
    }

    // MARK: Showing a list (U1 Ruling L)

    @Test("Entering the section on Closed reads the open list, then Closed once")
    func showEnteringClosed() async {
        let provider = FakeProvider()
        provider.open = [Self.pr(1, author: "me", sha: "a")]
        provider.closed = [Self.pr(9, author: "lucia", sha: "z")]
        let store = Self.makeStore(provider)

        await store.show(.closed, entering: true)

        #expect(provider.openFetches == 1)
        #expect(provider.closedFetches == 1)
        #expect(store.scope == .closed)
        #expect(store.visibleItems.map(\.number) == [9])
    }

    @Test("Switching to Closed on a store that never loaded reads the open list, then Closed once")
    func showClosedNeverLoaded() async {
        let provider = FakeProvider()
        provider.open = [Self.pr(1, author: "me", sha: "a")]
        provider.closed = [Self.pr(9, author: "lucia", sha: "z")]
        let store = Self.makeStore(provider)

        await store.show(.closed, entering: false)

        #expect(provider.openFetches == 1)
        #expect(provider.closedFetches == 1)
        #expect(store.visibleItems.map(\.number) == [9])
    }

    @Test("Switching between Open and Closed on a loaded store only changes the scope: Closed is read once")
    func showSwitchesScope() async {
        let provider = FakeProvider()
        provider.open = [Self.pr(1, author: "me", sha: "a")]
        provider.closed = [Self.pr(9, author: "lucia", sha: "z")]
        let store = Self.makeStore(provider)
        await store.load()

        await store.show(.open, entering: false)
        await store.show(.closed, entering: false)
        await store.show(.open, entering: false)
        await store.show(.closed, entering: false)

        #expect(provider.openFetches == 1)
        #expect(provider.closedFetches == 1)
        #expect(store.scope == .closed)
        #expect(store.visibleItems.map(\.number) == [9])
    }

    @Test("Entering the section again within the throttle reads nothing")
    func showEnteringWithinThrottle() async {
        let provider = FakeProvider()
        provider.open = [Self.pr(1, author: "me", sha: "a")]
        let store = Self.makeStore(provider)
        await store.show(.open, entering: true)

        await store.show(.open, entering: true)

        #expect(provider.openFetches == 1)
        #expect(provider.closedFetches == 0)
    }

    @Test("A store showing an error reads its list again when switched to, within the throttle too")
    func showReloadsOnError() async {
        let provider = FakeProvider()
        provider.open = [Self.pr(1, author: "me", sha: "a")]
        provider.openFailure = .network("offline")
        let store = Self.makeStore(provider)
        await store.load()
        #expect(store.error != nil)

        provider.openFailure = nil
        await store.show(.open, entering: false)
        #expect(provider.openFetches == 2)
        #expect(store.error == nil)
        #expect(store.visibleItems.map(\.number) == [1])

        // Loaded a moment ago, then Closed fails: back to Open, the list is read again.
        provider.closedFailure = .network("offline")
        await store.show(.closed, entering: false)
        #expect(store.error != nil)
        provider.closedFailure = nil
        await store.show(.open, entering: false)
        #expect(provider.openFetches == 3)
        #expect(store.error == nil)
        #expect(store.scope == .open)
    }

    @Test("Each row gets its own CI summary from its head commit's checks")
    func listCI() async {
        let provider = FakeProvider()
        provider.open = [Self.pr(1, author: "me", sha: "a"), Self.pr(2, author: "me", sha: "b"), Self.pr(3, author: "me", sha: "c")]
        provider.checksBySha = ["a": [Self.check(.passed)], "b": [Self.check(.passed), Self.check(.failed)]]
        let store = Self.makeStore(provider)
        await store.load(force: true)
        await Self.settle { store.ciByPull.count == 2 }
        #expect(store.ciByPull["1"]?.state == .success)
        #expect(store.ciByPull["2"]?.state == .failure)
        #expect(store.ciByPull["3"] == nil)
    }

    @Test("The open PR's checks load with its detail and drive its CI summary")
    func detailChecks() async {
        let provider = FakeProvider()
        provider.open = [Self.pr(1, author: "me", sha: "a")]
        provider.checksBySha = ["a": [Self.check(.running)]]
        let store = Self.makeStore(provider)
        await store.load(force: true)
        store.selected = provider.open[0]
        await store.loadDetail()
        #expect(store.checks.count == 1)
        #expect(store.ciStatus(for: provider.open[0])?.state == .pending)
    }

    // MARK: Commit CI

    @Test("A commit's checks come from the host and are reused within the TTL")
    func commitChecksCached() async {
        let provider = FakeProvider()
        provider.checksBySha["abc"] = [Self.check(.passed), Self.check(.failed)]
        let store = Self.makeStore(provider)
        #expect(await store.commitChecks(sha: "abc")?.map(\.state) == [.passed, .failed])
        #expect(await store.commitChecks(sha: "abc")?.count == 2)
        #expect(provider.commitCheckTokens.count == 1)
        _ = await store.commitChecks(sha: "abc", force: true)
        #expect(provider.commitCheckTokens.count == 2)
    }

    @Test("Commit checks ask for a token without prompting, and never touch the list state")
    func commitChecksSilentAuth() async {
        let provider = FakeProvider()
        provider.checksBySha["abc"] = [Self.check(.passed)]
        var prompted = 0
        let host = RemoteHost(provider: .github, host: "github.com", owner: "o", repo: "r")
        let store = PullRequestStore(
            cli: GitCLI(workingDirectory: URL(fileURLWithPath: "/var/empty")),
            auth: { _, _ in prompted += 1; return .token("interactive") },
            silentAuth: { _, _ in .token("silent") },
            resolveHost: { host },
            makeProvider: { _ in provider }
        )
        #expect(await store.commitChecks(sha: "abc")?.count == 1)
        #expect(prompted == 0)
        #expect(provider.commitCheckTokens == ["silent"])
        #expect(store.host == nil)
        #expect(!store.requiresToken)
    }

    @Test("No token without asking, or no recognised host: nothing to show")
    func commitChecksUnavailable() async {
        let provider = FakeProvider()
        let host = RemoteHost(provider: .github, host: "github.com", owner: "o", repo: "r")
        let noToken = PullRequestStore(
            cli: GitCLI(workingDirectory: URL(fileURLWithPath: "/var/empty")),
            silentAuth: { _, _ in .cancelled },
            resolveHost: { host },
            makeProvider: { _ in provider }
        )
        #expect(await noToken.commitChecks(sha: "abc") == nil)
        let noHost = PullRequestStore(
            cli: GitCLI(workingDirectory: URL(fileURLWithPath: "/var/empty")),
            auth: { _, _ in .token("token") },
            resolveHost: { nil },
            makeProvider: { _ in provider }
        )
        #expect(await noHost.commitChecks(sha: "abc") == nil)
        #expect(provider.commitCheckTokens.isEmpty)
    }
}
