import Foundation
import Testing
@testable import gitForge

/// Scripted provider: fixed lists and user, and a count of the open-list reads.
private final class FakeProvider: PullRequestProvider, @unchecked Sendable {
    var open: [PullRequest] = []
    var closed: [PullRequest] = []
    var user = "me"
    var checksBySha: [String: [CICheck]] = [:]
    private(set) var closedFetches = 0
    private(set) var openFetches = 0

    func fetchPulls(host: RemoteHost, state: PullListState, token: String) async throws -> [PullRequest] {
        if state == .closed { closedFetches += 1; return closed }
        openFetches += 1
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

/// Review writes that do nothing: the detail a selection opens reads its
/// threads and the Request changes support through them.
private struct InertReviews: PullRequestReviewProvider {
    func requestChangesSupport(host: RemoteHost, token: String) async -> RequestChangesSupport { .supported }
    func submitReview(host: RemoteHost, pull: PullRequest, verdict: ReviewVerdict,
                      body: String, token: String) async throws -> String? { nil }
    func fetchMergeOptions(host: RemoteHost, pull: PullRequest, detail: PullRequestDetail,
                           commits: [PullRequestCommit], token: String) async throws -> MergeOptions {
        throw PullRequestFetchError.notFound
    }
    func merge(host: RemoteHost, pull: PullRequest, input: MergeInput, token: String) async throws -> MergeOutcome {
        throw PullRequestFetchError.notFound
    }
    func fetchThreads(host: RemoteHost, pull: PullRequest, detail: PullRequestDetail?,
                      token: String) async throws -> [ReviewThread] { [] }
    func addComment(host: RemoteHost, pull: PullRequest, detail: PullRequestDetail?, target: CommentTarget,
                    body: String, token: String) async throws {}
    func reply(host: RemoteHost, pull: PullRequest, thread: ReviewThread, body: String, token: String) async throws {}
    func setResolved(_ resolved: Bool, host: RemoteHost, pull: PullRequest, thread: ReviewThread,
                     token: String) async throws {}
}

@Suite("PullRequestStore — without a local repository", .serialized)
@MainActor
struct PullRequestStoreRemoteTests {
    private static let host = RemoteHost(provider: .gitlab, host: "gitlab.example.test", owner: "team", repo: "app")

    /// The token the fake account gives, changed between calls.
    @MainActor private final class Account {
        var token: String
        init(token: String) { self.token = token }
    }

    private static func pr(_ number: Int) -> PullRequest {
        PullRequest(id: "\(number)", number: number, title: "PR \(number)", state: .open,
                    authorLogin: "marta", authorAvatarURL: nil, sourceBranch: "f/\(number)", targetBranch: "main",
                    webURL: nil, createdAt: nil, updatedAt: nil, headSha: nil)
    }

    @Test("A store without a local repo opens a PR without loading the list")
    func prepareForDetail() async {
        let provider = FakeProvider()
        provider.user = "marta"
        let host = Self.host
        let store = PullRequestStore(cli: nil, auth: { _, _ in .token("t") }, resolveHost: { host },
                                     makeProvider: { _ in provider })
        #expect(await store.prepareForDetail())
        #expect(store.host == host)
        #expect(store.currentUser == "marta")
        #expect(provider.openFetches == 0)
    }

    @Test("No token: the detail can't be prepared, and the store asks to connect")
    func prepareNoToken() async {
        let provider = FakeProvider()
        let host = Self.host
        let store = PullRequestStore(cli: nil, auth: { _, _ in .connectAccount(instanceId: nil, replacing: nil) },
                                     resolveHost: { host }, makeProvider: { _ in provider })
        #expect(await store.prepareForDetail() == false)
        #expect(store.requiresToken)
        #expect(provider.openFetches == 0)
    }

    @Test("Without a local repo and without a host to resolve, there is nothing to prepare")
    func prepareNoHost() async {
        let provider = FakeProvider()
        let store = PullRequestStore(cli: nil, auth: { _, _ in .token("t") }, makeProvider: { _ in provider })
        #expect(await store.prepareForDetail() == false)
        #expect(store.host == nil)
        #expect(provider.openFetches == 0)
    }

    @Test("The user is read again only when the token changes")
    func prepareReadsUserOnTokenChange() async {
        let provider = FakeProvider()
        provider.user = "marta"
        let host = Self.host
        let account = Account(token: "t1")
        let store = PullRequestStore(cli: nil, auth: { _, _ in .token(account.token) }, resolveHost: { host },
                                     makeProvider: { _ in provider })
        #expect(await store.prepareForDetail())
        provider.user = "other"
        #expect(await store.prepareForDetail())
        #expect(store.currentUser == "marta")
        account.token = "t2"
        #expect(await store.prepareForDetail())
        #expect(store.currentUser == "other")
    }

    @Test("A PR asked for before the list loads is the one auto-selected, once")
    func pendingSelection() async {
        let provider = FakeProvider()
        provider.open = [Self.pr(1), Self.pr(2)]
        let host = Self.host
        let store = PullRequestStore(cli: nil, auth: { _, _ in .token("t") }, resolveHost: { host },
                                     makeProvider: { _ in provider })
        store.selectWhenLoaded(number: 2)
        #expect(store.pendingSelectionNumber == 2)
        await store.load(force: true)
        #expect(store.pullToAutoSelect()?.number == 2)
        #expect(store.pendingSelectionNumber == nil)
        #expect(store.pullToAutoSelect()?.number == 1)
    }

    @Test("A PR asked for that isn't in the list yet stays pending for the next load")
    func pendingSelectionKept() async {
        let provider = FakeProvider()
        provider.open = [Self.pr(1)]
        let host = Self.host
        let store = PullRequestStore(cli: nil, auth: { _, _ in .token("t") }, resolveHost: { host },
                                     makeProvider: { _ in provider })
        store.selectWhenLoaded(number: 7)
        await store.load(force: true)
        #expect(store.pullToAutoSelect()?.number == 1)
        #expect(store.pendingSelectionNumber == 7)
        provider.open = [Self.pr(1), Self.pr(7)]
        await store.load(force: true)
        store.selected = Self.pr(1)
        #expect(store.pullToAutoSelect()?.number == 7)
        #expect(store.pendingSelectionNumber == nil)
    }

    @Test("A PR asked for that the list already shows opens at once, with nothing left pending")
    func requestedShownNow() async {
        let provider = FakeProvider()
        provider.open = [Self.pr(1), Self.pr(2)]
        let host = Self.host
        let store = PullRequestStore(cli: nil, auth: { _, _ in .token("t") }, resolveHost: { host },
                                     makeProvider: { _ in provider }, makeReviewProvider: { _ in InertReviews() })
        await store.load(force: true)
        store.selected = Self.pr(1)

        store.requestSelection(number: 2)

        #expect(store.selected?.number == 2)
        #expect(store.pendingSelectionNumber == nil)
        // A later reload doesn't jump back to it after the user moves on.
        store.selected = Self.pr(1)
        await store.load(force: true)
        #expect(store.pullToAutoSelect() == nil)
    }

    @Test("A PR asked for that the list doesn't show yet waits for it")
    func requestedLater() async {
        let provider = FakeProvider()
        provider.open = [Self.pr(1)]
        let host = Self.host
        let store = PullRequestStore(cli: nil, auth: { _, _ in .token("t") }, resolveHost: { host },
                                     makeProvider: { _ in provider })
        await store.load(force: true)

        store.requestSelection(number: 7)

        #expect(store.selected == nil)
        #expect(store.pendingSelectionNumber == 7)
        provider.open = [Self.pr(1), Self.pr(7)]
        await store.load(force: true)
        #expect(store.pullToAutoSelect()?.number == 7)
    }
}
