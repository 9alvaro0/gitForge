import Foundation
import Testing
@testable import gitForge

/// Scripted provider: fixed lists, user and checks, and a call log.
private final class FakeProvider: PullRequestProvider, @unchecked Sendable {
    var open: [PullRequest] = []
    var closed: [PullRequest] = []
    var user = "me"
    var checksBySha: [String: [CICheck]] = [:]
    private(set) var closedFetches = 0

    func fetchPulls(host: RemoteHost, state: PullListState, token: String) async throws -> [PullRequest] {
        if state == .closed { closedFetches += 1; return closed }
        return open
    }
    func fetchCurrentUser(host: RemoteHost, token: String) async throws -> String { user }
    func fetchChecks(host: RemoteHost, pull: PullRequest, token: String) async throws -> [CICheck] {
        checksBySha[pull.headSha ?? ""] ?? []
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
            token: { _ in "token" },
            resolveHost: { host },
            makeProvider: { _ in provider }
        )
    }

    /// The CI fill runs in a background task; give it a moment.
    private static func settle(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<100 where !condition() { try? await Task.sleep(for: .milliseconds(10)) }
    }

    @Test("Mine shows the open PRs authored by the token's user")
    func mine() async {
        let provider = FakeProvider()
        provider.open = [Self.pr(1, author: "me", sha: "a"), Self.pr(2, author: "lucia", sha: "b")]
        let store = Self.makeStore(provider)
        await store.load(force: true)
        await store.setScope(.mine)
        #expect(store.visibleItems.map(\.number) == [1])
        #expect(store.count(for: .mine) == 1)
        #expect(store.count(for: .open) == 2)
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
}
