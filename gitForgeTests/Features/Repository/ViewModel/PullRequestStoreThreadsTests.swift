import Foundation
import Testing
@testable import gitForge

/// Two open PRs by someone else, each with one file and the threads the
/// test sets. Thread reads and writes are recorded and can fail on demand;
/// a write can wait on `gate`.
private final class ThreadsFakeProvider: PullRequestProvider, PullRequestReviewProvider, @unchecked Sendable {
    enum Call: Equatable {
        case comment(number: Int, target: CommentTarget, body: String, head: String?)
        case reply(number: Int, threadId: String, body: String)
        case resolve(number: Int, threadId: String, resolved: Bool)
    }

    var threads: [Int: [ReviewThread]] = [:]
    var threadErrors: [Error] = []
    var writeErrors: [Error] = []
    var gate: AsyncGate?
    /// Holds thread reads (after the first) until the test opens it.
    var threadsGate: AsyncGate?
    /// PR 1's head per detail read, in order; the last repeats.
    var heads = ["sha1"]
    /// PR 1's check states per read, in order; the last repeats.
    var checkStates: [[CICheck.State]] = [[]]
    private(set) var calls: [Call] = []
    private(set) var threadFetches: [Int: Int] = [:]
    private(set) var detailFetches: [Int: Int] = [:]

    static let patch = "@@ -1,2 +1,3 @@\n a\n-b\n+c\n+d"

    static func pull(_ number: Int, head: String? = nil) -> PullRequest {
        PullRequest(id: "\(number)", number: number, title: "PR \(number)", state: .open, authorLogin: "marta",
                    authorAvatarURL: nil, sourceBranch: "feature/\(number)", targetBranch: "main", webURL: nil,
                    createdAt: nil, updatedAt: nil, headSha: head)
    }

    func fetchPulls(host: RemoteHost, state: PullListState, token: String) async throws -> [PullRequest] {
        state == .open ? [Self.pull(1), Self.pull(2)] : []
    }
    func fetchCurrentUser(host: RemoteHost, token: String) async throws -> String { "user-of-\(token)" }
    func fetchChecks(host: RemoteHost, pull: PullRequest, token: String) async throws -> [CICheck] {
        guard pull.number == 1 else { return [] }
        let states = checkStates.count > 1 ? checkStates.removeFirst() : checkStates.first ?? []
        return states.map { CICheck(name: "ci", context: nil, state: $0, duration: nil, failureMessage: nil, webURL: nil) }
    }
    func fetchCommitChecks(host: RemoteHost, sha: String, token: String) async throws -> [CICheck] { [] }
    func fetchDetail(host: RemoteHost, number: Int, token: String) async throws -> PullRequestDetail {
        detailFetches[number, default: 0] += 1
        let head = number == 1 ? (heads.count > 1 ? heads.removeFirst() : heads[0]) : "sha\(number)"
        return PullRequestDetail(pull: Self.pull(number, head: head), descriptionMarkdown: nil, labels: [], reviewers: [],
                                 assignees: [], mergeable: true, ciStatus: nil,
                                 hostMergeStatus: HostMergeStatus(verdict: .ready))
    }
    func fetchCommits(host: RemoteHost, number: Int, token: String) async throws -> [PullRequestCommit] { [] }
    func fetchFiles(host: RemoteHost, number: Int, token: String) async throws -> [PullRequestFileChange] {
        [PullRequestFileChange(path: "f\(number).swift", oldPath: nil, status: .modified, additions: 2, deletions: 1,
                               patch: Self.patch)]
    }

    func requestChangesSupport(host: RemoteHost, token: String) async -> RequestChangesSupport { .supported }
    func submitReview(host: RemoteHost, pull: PullRequest, verdict: ReviewVerdict, body: String, token: String) async throws -> String? { nil }
    func fetchMergeOptions(host: RemoteHost, pull: PullRequest, detail: PullRequestDetail,
                           commits: [PullRequestCommit], token: String) async throws -> MergeOptions {
        MergeOptions(kind: .github(methods: [.squash]), canDeleteSourceBranch: true, initialMethod: .squash, initialSquash: false)
    }
    func merge(host: RemoteHost, pull: PullRequest, input: MergeInput, token: String) async throws -> MergeOutcome {
        MergeOutcome(branchDeleted: false)
    }

    func fetchThreads(host: RemoteHost, pull: PullRequest, detail: PullRequestDetail?, token: String) async throws -> [ReviewThread] {
        threadFetches[pull.number, default: 0] += 1
        if let threadsGate, threadFetches[pull.number, default: 0] > 1 { await threadsGate.wait() }
        if !threadErrors.isEmpty { throw threadErrors.removeFirst() }
        return threads[pull.number] ?? []
    }
    func addComment(host: RemoteHost, pull: PullRequest, detail: PullRequestDetail?, target: CommentTarget,
                    body: String, token: String) async throws {
        calls.append(.comment(number: pull.number, target: target, body: body, head: detail?.pull.headSha))
        try await finishWrite()
    }
    func reply(host: RemoteHost, pull: PullRequest, thread: ReviewThread, body: String, token: String) async throws {
        calls.append(.reply(number: pull.number, threadId: thread.id, body: body))
        try await finishWrite()
    }
    func setResolved(_ resolved: Bool, host: RemoteHost, pull: PullRequest, thread: ReviewThread, token: String) async throws {
        calls.append(.resolve(number: pull.number, threadId: thread.id, resolved: resolved))
        try await finishWrite()
    }

    private func finishWrite() async throws {
        if let gate { await gate.wait() }
        if !writeErrors.isEmpty { throw writeErrors.removeFirst() }
    }
}

@Suite("PullRequestStore — threads", .serialized)
@MainActor
struct PullRequestStoreThreadsTests {
    nonisolated static let host = RemoteHost(provider: .github, host: "github.com", owner: "octo", repo: "app")

    private let provider = ThreadsFakeProvider()

    init() {
        PullRequestStore.mergeStatusRecheckDelay = .zero
        PullRequestStore.checksPollInterval = .milliseconds(5)
        PullRequestStore.checksPollLimit = 45
    }

    static func thread(_ id: String, path: String = "f1.swift", line: Int = 3, resolved: Bool = false) -> ReviewThread {
        ReviewThread(id: id, path: path, oldPath: nil, ref: DiffLineRef(side: .new, line: line), originalLine: line,
                     isResolved: resolved, isOutdated: false, resolvedBy: nil,
                     comments: [ReviewComment(id: "\(id)-c", authorLogin: "marta", authorAvatarURL: nil, body: "Why?", createdAt: nil)],
                     canReply: true, canResolve: !resolved, canUnresolve: resolved, replyToCommentId: "\(id)-c")
    }

    /// Line 3 of f1.swift, an added line.
    static let target = CommentTarget.make(path: "f1.swift", oldPath: nil,
                                           line: DiffLine(id: 2, kind: .added, content: "c", oldLineNumber: nil, newLineNumber: 3),
                                           side: .new)!

    /// A loaded list with PR 1's detail and threads open.
    private func loadedStore() async -> PullRequestStore {
        let provider = provider
        let store = PullRequestStore(cli: GitCLI(workingDirectory: URL(fileURLWithPath: "/var/empty")),
                                     auth: { _, rejected in rejected == nil ? .token("t1") : .token("t2") },
                                     resolveHost: { Self.host },
                                     makeProvider: { _ in provider },
                                     makeReviewProvider: { _ in provider })
        await store.load(force: true)
        store.selected = store.items.first
        await store.loadDetail()
        await store.mergeStatusRecheck?.value
        return store
    }

    @Test("Threads load with the detail and land under their line")
    func loadsWithDetail() async {
        provider.threads[1] = [Self.thread("T1")]
        let store = await loadedStore()
        #expect(store.threads.map(\.id) == ["T1"])
        #expect(store.placedThreads.inline["f1.swift"]?[DiffLineRef(side: .new, line: 3)]?.map(\.id) == ["T1"])
        #expect(store.placedThreads.openCount(for: "f1.swift") == 1)
        #expect(provider.threadFetches[1] == 1)
    }

    @Test("Threads failing don't fail the detail")
    func threadsFailing() async {
        provider.threadErrors = [PullRequestFetchError.server(500, "x")]
        let store = await loadedStore()
        #expect(store.detailError == nil)
        #expect(store.threadsError != nil)
        #expect(store.files.count == 1)
        #expect(store.detail != nil)
        await store.loadThreads()
        #expect(store.threadsError == nil)
    }

    @Test("Refresh keeps the draft and the open composer")
    func refreshKeepsComposer() async {
        let store = await loadedStore()
        store.composerTarget = Self.target
        store.drafts[.comment(pullId: "1", target: Self.target)] = "WIP"
        await store.refresh()
        #expect(store.composerTarget == Self.target)
        #expect(store.drafts[.comment(pullId: "1", target: Self.target)] == "WIP")
        #expect(provider.detailFetches[1] == 2)
        #expect(provider.threadFetches[1] == 2)
    }

    @Test("Refresh and the CI poll keep an open reply box and its text")
    func refreshAndPollKeepReply() async {
        provider.threads[1] = [Self.thread("T1")]
        provider.checkStates = [[.running], [.running], [.passed]]
        let store = await loadedStore()
        store.replyingThreadId = "T1"
        store.drafts[.reply(pullId: "1", threadId: "T1")] = "Half a sentence"
        let poll = Task { await store.pollWhileRunning() }
        await waitUntil { store.checks.map(\.state) == [.passed] }
        poll.cancel()
        await store.refresh()
        #expect(store.replyingThreadId == "T1")
        #expect(store.drafts[.reply(pullId: "1", threadId: "T1")] == "Half a sentence")
        #expect(store.threads.map(\.id) == ["T1"])
    }

    @Test("Opening a box closes the other one; their drafts stay")
    func oneComposerAtATime() async {
        let store = await loadedStore()
        store.drafts[.comment(pullId: "1", target: Self.target)] = "A"
        store.composerTarget = Self.target
        store.replyingThreadId = "T1"
        #expect(store.composerTarget == nil)
        store.composerTarget = Self.target
        #expect(store.replyingThreadId == nil)
        #expect(store.drafts[.comment(pullId: "1", target: Self.target)] == "A")
    }

    @Test("A new comment is sent once, clears its draft and reloads the threads")
    func newComment() async {
        let store = await loadedStore()
        store.composerTarget = Self.target
        store.drafts[.comment(pullId: "1", target: Self.target)] = "  Why not 5?\n"
        #expect(await store.addComment(at: Self.target) == .done)
        #expect(provider.calls == [.comment(number: 1, target: Self.target, body: "Why not 5?", head: "sha1")])
        #expect(store.drafts[.comment(pullId: "1", target: Self.target)] == nil)
        #expect(store.composerTarget == nil)
        #expect(store.sendingDrafts.isEmpty)
        #expect(provider.threadFetches[1] == 2)
    }

    @Test("A blank comment isn't sent")
    func blankComment() async {
        let store = await loadedStore()
        store.drafts[.comment(pullId: "1", target: Self.target)] = " \n "
        #expect(await store.addComment(at: Self.target) == .ignored)
        #expect(provider.calls.isEmpty)
    }

    @Test("A reply goes to its thread and closes the box")
    func reply() async {
        provider.threads[1] = [Self.thread("T1")]
        let store = await loadedStore()
        store.replyingThreadId = "T1"
        store.drafts[.reply(pullId: "1", threadId: "T1")] = "Done"
        #expect(await store.reply(to: store.threads[0]) == .done)
        #expect(provider.calls == [.reply(number: 1, threadId: "T1", body: "Done")])
        #expect(store.replyingThreadId == nil)
        #expect(store.drafts[.reply(pullId: "1", threadId: "T1")] == nil)
        #expect(provider.threadFetches[1] == 2)
    }

    @Test("Someone else changed the thread: reload and keep the draft")
    func changedOnHost() async {
        provider.threads[1] = [Self.thread("T1")]
        let store = await loadedStore()
        store.drafts[.reply(pullId: "1", threadId: "T1")] = "Done"
        provider.writeErrors = [PullRequestFetchError.notFound]
        #expect(await store.reply(to: store.threads[0]) == .changedOnHost("It changed on the host since it loaded."))
        #expect(store.drafts[.reply(pullId: "1", threadId: "T1")] == "Done")
        #expect(provider.threadFetches[1] == 2)
    }

    @Test("A refusal says which account can't, and keeps the draft")
    func forbidden() async {
        let store = await loadedStore()
        store.drafts[.comment(pullId: "1", target: Self.target)] = "x"
        provider.writeErrors = [PullRequestActionError.forbidden]
        #expect(await store.addComment(at: Self.target)
                == .failed("Your account (user-of-t1 on github.com) can't comment on this pull request."))
        #expect(store.drafts[.comment(pullId: "1", target: Self.target)] == "x")
        #expect(provider.threadFetches[1] == 1)
    }

    @Test("New commits on the host: the detail and the threads reload, the draft stays")
    func headChanged() async {
        let store = await loadedStore()
        store.drafts[.comment(pullId: "1", target: Self.target)] = "x"
        provider.writeErrors = [PullRequestActionError.headChanged]
        #expect(await store.addComment(at: Self.target) == .changedOnHost("New commits were pushed — review them and try again."))
        #expect(provider.detailFetches[1] == 2)
        #expect(provider.threadFetches[1] == 2)
        #expect(store.drafts[.comment(pullId: "1", target: Self.target)] == "x")
    }

    @Test("A 401 gets one fresh token and one retry")
    func retriesAfter401() async {
        let store = await loadedStore()
        store.drafts[.comment(pullId: "1", target: Self.target)] = "x"
        provider.writeErrors = [PullRequestFetchError.unauthorized]
        #expect(await store.addComment(at: Self.target) == .done)
        #expect(provider.calls.count == 2)
    }

    @Test("Resolving updates the thread in place")
    func resolveInPlace() async {
        provider.threads[1] = [Self.thread("T1")]
        let store = await loadedStore()
        #expect(await store.setResolved(true, thread: store.threads[0]) == .done)
        #expect(provider.calls == [.resolve(number: 1, threadId: "T1", resolved: true)])
        #expect(store.threads[0].isResolved)
        #expect(store.threads[0].resolvedBy == "user-of-t1")
        #expect(store.threads[0].canUnresolve && !store.threads[0].canResolve)
        #expect(store.placedThreads.openCount(for: "f1.swift") == 0)
        #expect(provider.threadFetches[1] == 1)
        #expect(store.resolvingThreadIds.isEmpty)

        #expect(await store.setResolved(false, thread: store.threads[0]) == .done)
        #expect(!store.threads[0].isResolved && store.threads[0].resolvedBy == nil && store.threads[0].canResolve)
    }

    @Test("Resolving a thread someone deleted reloads the threads")
    func resolveGone() async {
        provider.threads[1] = [Self.thread("T1")]
        let store = await loadedStore()
        provider.threads[1] = []
        provider.writeErrors = [PullRequestActionError.changedOnHost]
        #expect(await store.setResolved(true, thread: store.threads[0]) == .changedOnHost("It changed on the host since it loaded."))
        #expect(store.threads.isEmpty)
    }

    @Test("Drafts survive switching PRs")
    func draftsSurviveSwitching() async throws {
        let store = await loadedStore()
        store.drafts[.reply(pullId: "1", threadId: "T1")] = "Keep me"
        store.composerTarget = Self.target
        let second = try #require(store.items.last)
        store.select(second)
        #expect(store.composerTarget == nil && store.threads.isEmpty && store.replyingThreadId == nil)
        await waitUntil { store.detail?.pull.number == 2 && !store.isLoadingDetail }
        store.select(try #require(store.items.first))
        await waitUntil { store.detail?.pull.number == 1 && !store.isLoadingDetail }
        #expect(store.drafts[.reply(pullId: "1", threadId: "T1")] == "Keep me")
    }

    @Test("The comment goes to the PR it was written on")
    func commentStaysOnItsPR() async throws {
        provider.threads[2] = [Self.thread("T2", path: "f2.swift")]
        let store = await loadedStore()
        store.drafts[.comment(pullId: "1", target: Self.target)] = "On PR 1"
        let gate = AsyncGate()
        provider.gate = gate
        let send = Task { await store.addComment(at: Self.target) }
        await gate.waiting()
        store.select(try #require(store.items.last))
        await waitUntil { store.detail?.pull.number == 2 && !store.isLoadingDetail && store.threads.map(\.id) == ["T2"] }
        gate.open()
        #expect(await send.value == .done)
        #expect(provider.calls == [.comment(number: 1, target: Self.target, body: "On PR 1", head: "sha1")])
        #expect(store.threads.map(\.id) == ["T2"])
        #expect(provider.threadFetches[1] == 1)
        #expect(store.drafts[.comment(pullId: "1", target: Self.target)] == nil)
    }

    @Test("Resolving two threads in a row: both reach the host")
    func twoResolves() async {
        provider.threads[1] = [Self.thread("T1"), Self.thread("T2", line: 4)]
        let store = await loadedStore()
        let gate = AsyncGate()
        provider.gate = gate
        let first = Task { await store.setResolved(true, thread: store.threads[0]) }
        await gate.waiting()
        let second = Task { await store.setResolved(true, thread: store.threads[1]) }
        await waitUntil { provider.calls.count == 2 }
        #expect(store.resolvingThreadIds == ["T1", "T2"])
        gate.open()
        #expect(await first.value == .done)
        #expect(await second.value == .done)
        #expect(store.threads.allSatisfy { $0.isResolved })
    }

    @Test("A send still going on one PR doesn't block one on another")
    func sendsOnTwoPRs() async throws {
        let store = await loadedStore()
        store.drafts[.comment(pullId: "1", target: Self.target)] = "On PR 1"
        let gate = AsyncGate()
        provider.gate = gate
        let first = Task { await store.addComment(at: Self.target) }
        await gate.waiting()
        store.select(try #require(store.items.last))
        await waitUntil { store.detail?.pull.number == 2 && !store.isLoadingDetail }
        let target2 = try #require(CommentTarget.make(path: "f2.swift", oldPath: nil, line: DiffLine(
            id: 2, kind: .added, content: "c", oldLineNumber: nil, newLineNumber: 3), side: .new))
        store.drafts[.comment(pullId: "2", target: target2)] = "On PR 2"
        let second = Task { await store.addComment(at: target2) }
        await waitUntil { provider.calls.count == 2 }
        gate.open()
        #expect(await first.value == .done)
        #expect(await second.value == .done)
    }

    @Test("Once posted, the box is free again while the threads reload")
    func sendFreedBeforeReload() async {
        provider.threads[1] = [Self.thread("T1")]
        let store = await loadedStore()
        store.replyingThreadId = "T1"
        store.drafts[.reply(pullId: "1", threadId: "T1")] = "Done"
        let gate = AsyncGate()
        provider.threadsGate = gate
        let send = Task { await store.reply(to: store.threads[0]) }
        await gate.waiting()
        #expect(store.sendingDrafts.isEmpty)
        #expect(store.replyingThreadId == nil)
        gate.open()
        #expect(await send.value == .done)
    }

    @Test("New commits on Refresh close the new-comment box: its line may be other code now; the draft stays")
    func newHeadClosesComposer() async {
        provider.heads = ["sha1", "sha2"]
        let store = await loadedStore()
        store.composerTarget = Self.target
        store.drafts[.comment(pullId: "1", target: Self.target)] = "WIP"
        await store.refresh()
        #expect(store.composerTarget == nil)
        #expect(store.drafts[.comment(pullId: "1", target: Self.target)] == "WIP")
    }

    @Test("A new head read by the CI poll doesn't move comments off the diff on screen")
    func pinnedToShownDiff() async {
        provider.heads = ["sha1", "sha1-new"]
        provider.checkStates = [[.running], [.passed]]
        let store = await loadedStore()
        let poll = Task { await store.pollWhileRunning() }
        await waitUntil { store.detail?.pull.headSha == "sha1-new" }
        poll.cancel()
        store.drafts[.comment(pullId: "1", target: Self.target)] = "x"
        #expect(await store.addComment(at: Self.target) == .done)
        #expect(provider.calls == [.comment(number: 1, target: Self.target, body: "x", head: "sha1")])
    }
}
