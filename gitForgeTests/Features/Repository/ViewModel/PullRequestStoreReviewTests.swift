import Foundation
import Testing
@testable import gitForge

/// Two open PRs by someone else, a fixed detail per number, and how often
/// each detail was fetched. `detailGate` holds the reads after the first.
private final class ReviewFakeProvider: PullRequestProvider, @unchecked Sendable {
    private(set) var detailFetches: [Int: Int] = [:]
    var detailGate: AsyncGate?
    /// Reads after the first say the PR was merged meanwhile.
    var mergedOnReload = false

    static func pull(_ number: Int) -> PullRequest {
        PullRequest(id: "\(number)", number: number, title: "PR \(number)", state: .open, authorLogin: "marta",
                    authorAvatarURL: nil, sourceBranch: "feature/\(number)", targetBranch: "main", webURL: nil,
                    createdAt: nil, updatedAt: nil, headSha: "sha\(number)")
    }

    func fetchPulls(host: RemoteHost, state: PullListState, token: String) async throws -> [PullRequest] {
        state == .open ? [Self.pull(1), Self.pull(2)] : []
    }
    func fetchCurrentUser(host: RemoteHost, token: String) async throws -> String { "user-of-\(token)" }
    func fetchChecks(host: RemoteHost, pull: PullRequest, token: String) async throws -> [CICheck] { [] }
    func fetchCommitChecks(host: RemoteHost, sha: String, token: String) async throws -> [CICheck] { [] }
    func fetchDetail(host: RemoteHost, number: Int, token: String) async throws -> PullRequestDetail {
        detailFetches[number, default: 0] += 1
        if let detailGate, detailFetches[number, default: 0] > 1 { await detailGate.wait() }
        var pull = Self.pull(number)
        if mergedOnReload, detailFetches[number, default: 0] > 1 { pull.state = .merged }
        return PullRequestDetail(pull: pull, descriptionMarkdown: nil, labels: [], reviewers: [], assignees: [],
                                 mergeable: true, ciStatus: nil)
    }
    func fetchCommits(host: RemoteHost, number: Int, token: String) async throws -> [PullRequestCommit] { [] }
    func fetchFiles(host: RemoteHost, number: Int, token: String) async throws -> [PullRequestFileChange] { [] }
}

/// Records each review, throws what the test queues, and can hold a review
/// until the test opens `gate`.
private final class FakeReviewProvider: PullRequestReviewProvider, @unchecked Sendable {
    struct Call: Equatable {
        let number: Int
        let verdict: ReviewVerdict
        let body: String
        let token: String
    }
    private(set) var calls: [Call] = []
    private(set) var landed: [Call] = []
    var errors: [Error] = []
    var warning: String?
    var gate: AsyncGate?
    /// Holds the Request changes probe until the test opens it.
    var supportGate: AsyncGate?

    func requestChangesSupport(host: RemoteHost, token: String) async -> RequestChangesSupport {
        if let supportGate { await supportGate.wait() }
        return .supported
    }

    func submitReview(host: RemoteHost, pull: PullRequest, verdict: ReviewVerdict, body: String, token: String) async throws -> String? {
        let call = Call(number: pull.number, verdict: verdict, body: body, token: token)
        calls.append(call)
        if let gate { await gate.wait() }
        if !errors.isEmpty { throw errors.removeFirst() }
        landed.append(call)
        return warning
    }

    func fetchMergeOptions(host: RemoteHost, pull: PullRequest, detail: PullRequestDetail,
                           commits: [PullRequestCommit], token: String) async throws -> MergeOptions {
        MergeOptions(kind: .github(methods: [.squash]), canDeleteSourceBranch: true, initialMethod: .squash, initialSquash: false)
    }

    func merge(host: RemoteHost, pull: PullRequest, input: MergeInput, token: String) async throws -> MergeOutcome {
        MergeOutcome(branchDeleted: input.deleteSourceBranch)
    }

    func fetchThreads(host: RemoteHost, pull: PullRequest, detail: PullRequestDetail?, token: String) async throws -> [ReviewThread] {
        []
    }
    func addComment(host: RemoteHost, pull: PullRequest, detail: PullRequestDetail?, target: CommentTarget,
                    body: String, token: String) async throws {}
    func reply(host: RemoteHost, pull: PullRequest, thread: ReviewThread, body: String, token: String) async throws {}
    func setResolved(_ resolved: Bool, host: RemoteHost, pull: PullRequest, thread: ReviewThread, token: String) async throws {}
}

/// The tokens `auth` was told were rejected.
@MainActor
private final class AuthLog {
    var rejected: [String] = []
    /// The account is gone: `auth` asks to connect one.
    var disconnected = false
}

/// Set once a call the test started has come back.
@MainActor
private final class Answered {
    var value = false
}

@Suite("PullRequestStore — reviews", .serialized)
@MainActor
struct PullRequestStoreReviewTests {
    nonisolated static let host = RemoteHost(provider: .github, host: "github.com", owner: "octo", repo: "app")

    private let provider = ReviewFakeProvider()
    private let reviews = FakeReviewProvider()
    private let auth = AuthLog()

    /// A loaded list with PR 1's detail open (loaded directly, so the fetch
    /// count is deterministic), unless `loadingDetail` is false.
    private func loadedStore(host: RemoteHost = Self.host, loadingDetail: Bool = true) async -> PullRequestStore {
        let provider = provider
        let reviews = reviews
        let auth = auth
        let store = PullRequestStore(cli: GitCLI(workingDirectory: URL(fileURLWithPath: "/var/empty")),
                                     auth: { _, rejected in
                                         if auth.disconnected { return .connectAccount(instanceId: nil, replacing: nil) }
                                         if let rejected { auth.rejected.append(rejected) }
                                         return rejected == nil ? .token("t1") : .token("t2")
                                     },
                                     resolveHost: { host },
                                     makeProvider: { _ in provider },
                                     makeReviewProvider: { _ in reviews })
        await store.load(force: true)
        store.selected = store.items.first
        if loadingDetail { await store.loadDetail() }
        return store
    }

    @Test("Request changes with only spaces isn't sent")
    func blankRequestChanges() async {
        let store = await loadedStore()
        store.drafts[.review(pullId: "1", .requestChanges)] = "  \n"
        #expect(await store.submitReview(.requestChanges) == .ignored)
        #expect(reviews.calls.isEmpty)
    }

    @Test("Approve sends the draft, clears it and reloads the detail")
    func approve() async {
        let store = await loadedStore()
        store.drafts[.review(pullId: "1", .approve)] = "LGTM"
        #expect(await store.submitReview(.approve) == .submitted(warning: nil))
        #expect(reviews.landed == [.init(number: 1, verdict: .approve, body: "LGTM", token: "t1")])
        #expect(store.drafts[.review(pullId: "1", .approve)] == nil)
        #expect(store.submittingReview == nil)
        await waitUntil { provider.detailFetches[1] == 2 && !store.isLoadingDetail }
        #expect(provider.detailFetches[1] == 2)
    }

    @Test("A landed review answers before the detail reloads; the reload follows")
    func answersBeforeReload() async {
        let store = await loadedStore()
        let gate = AsyncGate()
        provider.detailGate = gate
        let answered = Answered()
        let submit = Task {
            let result = await store.submitReview(.approve)
            answered.value = true
            return result
        }
        await gate.waiting()
        await waitUntil(timeout: .seconds(2)) { answered.value }
        #expect(answered.value)
        #expect(store.submittingReview == nil)
        #expect(store.isLoadingDetail)
        gate.open()
        #expect(await submit.value == .submitted(warning: nil))
        await waitUntil { !store.isLoadingDetail }
        #expect(provider.detailFetches[1] == 2)
    }

    @Test("A refused review answers before the detail reloads")
    func refusalAnswersBeforeReload() async {
        let store = await loadedStore()
        let gate = AsyncGate()
        provider.detailGate = gate
        reviews.errors = [PullRequestActionError.rejected("no")]
        let answered = Answered()
        let submit = Task {
            let result = await store.submitReview(.approve)
            answered.value = true
            return result
        }
        await gate.waiting()
        await waitUntil(timeout: .seconds(2)) { answered.value }
        #expect(answered.value)
        gate.open()
        _ = await submit.value
        await waitUntil { !store.isLoadingDetail }
        #expect(provider.detailFetches[1] == 2)
    }

    @Test("A 401 gets one fresh token and one retry")
    func retriesAfter401() async {
        let store = await loadedStore()
        reviews.errors = [PullRequestFetchError.unauthorized]
        #expect(await store.submitReview(.approve) == .submitted(warning: nil))
        #expect(reviews.calls.map(\.token) == ["t1", "t2"])
        #expect(reviews.landed.count == 1)
    }

    @Test("A 403 says which account can't, and keeps the draft")
    func forbidden() async {
        let store = await loadedStore()
        store.drafts[.review(pullId: "1", .approve)] = "LGTM"
        reviews.errors = [PullRequestFetchError.forbidden]
        #expect(await store.submitReview(.approve)
                == .failed("#1: Your account (user-of-t1 on github.com) can't approve this pull request."))
        #expect(store.drafts[.review(pullId: "1", .approve)] == "LGTM")
        #expect(store.submittingReview == nil)
    }

    @Test("GitLab: approval kept when the comment fails")
    func warning() async {
        let store = await loadedStore()
        reviews.warning = "Approved, but the comment couldn't be posted: boom"
        #expect(await store.submitReview(.approve) == .submitted(warning: "#1: Approved, but the comment couldn't be posted: boom"))
    }

    @Test("Switching PR mid-submit: the review goes to the first PR and the second isn't reloaded by it")
    func switchMidSubmit() async throws {
        let store = await loadedStore()
        let gate = AsyncGate()
        reviews.gate = gate
        let submit = Task { await store.submitReview(.approve) }
        await gate.waiting()
        let second = try #require(store.items.last)
        store.select(second)
        await waitUntil { store.detail?.pull.number == 2 && !store.isLoadingDetail }
        gate.open()
        #expect(await submit.value == .submitted(warning: nil))
        // A reload of the wrong PR would run in the background: give it time.
        await waitUntil(timeout: .milliseconds(300)) { provider.detailFetches[1] != 1 || provider.detailFetches[2] != 1 }
        #expect(reviews.landed.map(\.number) == [1])
        #expect(provider.detailFetches[2] == 1)
        #expect(provider.detailFetches[1] == 1)
        #expect(store.detail?.pull.number == 2)
    }

    @Test("A refused review never asks for a fresh token, and reloads the detail")
    func refused() async {
        let store = await loadedStore()
        reviews.errors = [PullRequestActionError.rejected("the approval wasn't accepted")]
        #expect(await store.submitReview(.approve) == .failed("#1: The host refused: the approval wasn't accepted"))
        #expect(auth.rejected.isEmpty)
        await waitUntil { provider.detailFetches[1] == 2 && !store.isLoadingDetail }
        #expect(provider.detailFetches[1] == 2)
    }

    @Test("New commits on the host: says so, reloads the detail and keeps the draft")
    func headChanged() async {
        let store = await loadedStore()
        store.drafts[.review(pullId: "1", .requestChanges)] = "Add tests"
        reviews.errors = [PullRequestFetchError.server(409, "{}")]
        #expect(await store.submitReview(.requestChanges) == .failed("#1: New commits were pushed — review them and try again."))
        await waitUntil { provider.detailFetches[1] == 2 && !store.isLoadingDetail }
        #expect(provider.detailFetches[1] == 2)
        #expect(store.drafts[.review(pullId: "1", .requestChanges)] == "Add tests")
    }

    @Test("A failure names the PR it was on, as GitLab writes it")
    func failureNamesMergeRequest() async {
        let gitlab = RemoteHost(provider: .gitlab, host: "gitlab.com", owner: "octo", repo: "app")
        let store = await loadedStore(host: gitlab)
        reviews.errors = [PullRequestFetchError.forbidden]
        #expect(await store.submitReview(.approve)
                == .failed("!1: Your account (user-of-t1 on gitlab.com) can't approve this merge request."))
    }

    @Test("A failure that lands after switching PRs still names the PR it was on")
    func failureAfterSwitchNamesItsPR() async throws {
        let store = await loadedStore()
        let gate = AsyncGate()
        reviews.gate = gate
        reviews.errors = [PullRequestFetchError.forbidden]
        let submit = Task { await store.submitReview(.approve) }
        await gate.waiting()
        store.select(try #require(store.items.last))
        gate.open()
        #expect(await submit.value == .failed("#1: Your account (user-of-t1 on github.com) can't approve this pull request."))
    }

    @Test("A verdict that landed without its comment keeps the comment's draft")
    func warningKeepsDraft() async {
        let store = await loadedStore()
        store.drafts[.review(pullId: "1", .approve)] = "LGTM"
        reviews.warning = "Approved, but the comment couldn't be posted: boom"
        #expect(await store.submitReview(.approve) == .submitted(warning: "#1: Approved, but the comment couldn't be posted: boom"))
        #expect(store.drafts[.review(pullId: "1", .approve)] == "LGTM")
    }

    @Test("Until the reload after a review is in, the buttons stay off and a second review isn't sent")
    func busyUntilReloadLands() async {
        let store = await loadedStore()
        let gate = AsyncGate()
        provider.detailGate = gate
        #expect(await store.submitReview(.approve) == .submitted(warning: nil))
        await gate.waiting()
        #expect(store.isReviewBusy)
        #expect(await store.submitReview(.approve) == .ignored)
        #expect(reviews.calls.count == 1)
        gate.open()
        await waitUntil { !store.isReviewBusy }
        #expect(!store.isReviewBusy)
        #expect(!store.isLoadingDetail)
    }

    @Test("A reload that loses the token on the way doesn't leave the detail spinning")
    func lostTokenClearsLoading() async {
        let store = await loadedStore()
        let gate = AsyncGate()
        provider.detailGate = gate
        _ = await store.submitReview(.approve)
        await gate.waiting()
        #expect(store.isLoadingDetail)
        auth.disconnected = true
        await store.refresh()
        gate.open()
        await waitUntil(timeout: .seconds(2)) { !store.isLoadingDetail }
        #expect(!store.isLoadingDetail)
    }

    @Test("A panel whose action the reloaded PR no longer offers closes")
    func panelClosesWhenActionGoes() async {
        let store = await loadedStore()
        store.reviewPanel = .requestChanges
        store.drafts[.review(pullId: "1", .requestChanges)] = "Add tests"
        provider.mergedOnReload = true
        reviews.errors = [PullRequestActionError.rejected("it was merged")]
        _ = await store.submitReview(.requestChanges)
        await waitUntil { store.detail?.pull.state == .merged && !store.isLoadingDetail }
        #expect(store.reviewPanel == nil)
        #expect(store.drafts[.review(pullId: "1", .requestChanges)] == "Add tests")
    }

    @Test("A landed review closes its panel, with or without its comment")
    func landedClosesPanel() async {
        let store = await loadedStore()
        store.reviewPanel = .approve
        #expect(await store.submitReview(.approve) == .submitted(warning: nil))
        #expect(store.reviewPanel == nil)
        // The buttons are back once the reload is in.
        await waitUntil { !store.isReviewBusy }

        reviews.warning = "Approved, but the comment couldn't be posted: boom"
        store.reviewPanel = .approve
        _ = await store.submitReview(.approve)
        #expect(store.reviewPanel == nil)
    }

    @Test("A failed review keeps its panel open")
    func failureKeepsPanel() async {
        let store = await loadedStore()
        store.reviewPanel = .requestChanges
        store.drafts[.review(pullId: "1", .requestChanges)] = "Add tests"
        reviews.errors = [PullRequestFetchError.forbidden]
        _ = await store.submitReview(.requestChanges)
        #expect(store.reviewPanel == .requestChanges)
    }

    @Test("Reloading the detail keeps the panel open; another PR closes it")
    func panelAcrossReloadsAndPRs() async throws {
        let store = await loadedStore()
        store.reviewPanel = .approve
        await store.loadDetail()
        #expect(store.reviewPanel == .approve)
        store.select(try #require(store.items.last))
        #expect(store.reviewPanel == nil)
    }

    @Test("The detail doesn't wait for the Request changes probe; its answer lands when it comes")
    func probeDoesNotHoldDetail() async {
        let gate = AsyncGate()
        reviews.supportGate = gate
        let store = await loadedStore(loadingDetail: false)
        let answered = Answered()
        let load = Task {
            await store.loadDetail()
            answered.value = true
        }
        await gate.waiting()
        await waitUntil(timeout: .seconds(2)) { answered.value }
        #expect(answered.value)
        #expect(!store.isLoadingDetail)
        #expect(store.detail?.pull.number == 1)
        #expect(store.requestChangesSupport == nil)
        gate.open()
        await load.value
        await waitUntil { store.requestChangesSupport != nil }
        #expect(store.requestChangesSupport == .supported)
    }

    @Test("A probe that answers after the repo closed lands nowhere")
    func lateProbeAfterReset() async {
        let gate = AsyncGate()
        reviews.supportGate = gate
        let store = await loadedStore(loadingDetail: false)
        let load = Task { await store.loadDetail() }
        await gate.waiting()
        store.reset()
        gate.open()
        await load.value
        await waitUntil(timeout: .milliseconds(300)) { store.requestChangesSupport != nil }
        #expect(store.requestChangesSupport == nil)
    }

    @Test("Request changes support is read with the detail")
    func support() async {
        let store = await loadedStore()
        await waitUntil { store.requestChangesSupport != nil }
        #expect(store.requestChangesSupport == .supported)
        #expect(store.reviewActions == ReviewActions(approve: .available, requestChanges: .available))
    }
}
