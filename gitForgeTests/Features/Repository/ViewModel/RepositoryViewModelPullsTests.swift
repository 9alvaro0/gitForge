import Foundation
import Testing
@testable import gitForge

@Suite("RepositoryViewModel — pull request detail state", .serialized)
@MainActor
struct RepositoryViewModelPullDetailTests {

    private static func makeVM() -> RepositoryViewModel {
        let url = URL(fileURLWithPath: "/var/empty/gitForge-tests-\(UUID().uuidString)")
        return RepositoryViewModel(repository: Repository(url: url))
    }

    private static func pr(_ number: Int) -> PullRequest {
        PullRequest(
            id: "\(number)",
            number: number,
            title: "PR #\(number)",
            state: .open,
            authorLogin: nil,
            authorAvatarURL: nil,
            sourceBranch: "feature/\(number)",
            targetBranch: "main",
            webURL: nil,
            createdAt: nil,
            updatedAt: nil
        )
    }

    @Test("selectPullRequest clears prior detail state and bumps the gen-token")
    func selectClearsAndBumps() {
        let vm = Self.makeVM()
        // Pre-seed detail state from a previous PR.
        vm.pullRequestDetail = nil
        vm.pullRequestCommits = []
        vm.pullRequestFiles = []
        vm.pullRequestDetailError = "stale error"
        let beforeGen = vm.pullRequestDetailGen

        vm.selectPullRequest(Self.pr(42))

        #expect(vm.selectedPullRequest?.number == 42)
        #expect(vm.pullRequestDetail == nil)
        #expect(vm.pullRequestCommits.isEmpty)
        #expect(vm.pullRequestFiles.isEmpty)
        #expect(vm.pullRequestDetailError == nil)
        #expect(vm.pullRequestDetailGen == beforeGen &+ 1)
    }

    @Test("closePullRequestDetail clears state and bumps the gen-token")
    func closeClearsAndBumps() {
        let vm = Self.makeVM()
        vm.selectedPullRequest = Self.pr(42)
        vm.pullRequestDetailError = "old"
        let beforeGen = vm.pullRequestDetailGen

        vm.closePullRequestDetail()

        #expect(vm.selectedPullRequest == nil)
        #expect(vm.pullRequestDetail == nil)
        #expect(vm.pullRequestCommits.isEmpty)
        #expect(vm.pullRequestFiles.isEmpty)
        #expect(vm.pullRequestDetailError == nil)
        #expect(vm.pullRequestDetailGen == beforeGen &+ 1)
    }

    @Test("loadPullRequestDetail short-circuits when no PR is selected")
    func loadDetailNoPR() async {
        let vm = Self.makeVM()
        // Bump once to detect the early-return: the function bumps the token
        // before it can short-circuit on the missing PR.
        let beforeGen = vm.pullRequestDetailGen
        await vm.loadPullRequestDetail()
        #expect(vm.pullRequestDetailGen == beforeGen &+ 1)
        #expect(vm.pullRequestDetail == nil)
        #expect(vm.pullRequestDetailError == nil)
    }
}

@Suite("RepositoryViewModel — local PR merge guards", .serialized)
@MainActor
struct RepositoryViewModelPullMergeGuardsTests {

    private static func makeVM() -> RepositoryViewModel {
        let url = URL(fileURLWithPath: "/var/empty/gitForge-tests-\(UUID().uuidString)")
        return RepositoryViewModel(repository: Repository(url: url))
    }

    private static func pr() -> PullRequest {
        PullRequest(
            id: "1", number: 1, title: "T", state: .open,
            authorLogin: nil, authorAvatarURL: nil,
            sourceBranch: "feature/x", targetBranch: "main",
            webURL: nil, createdAt: nil, updatedAt: nil
        )
    }

    @Test("attemptLocalMergeForPullRequest fails when no PR is selected")
    func failsWithoutSelection() async {
        let vm = Self.makeVM()
        let outcome = await vm.attemptLocalMergeForPullRequest()
        guard case .failed(let message) = outcome else {
            Issue.record("Expected .failed, got \(outcome)")
            return
        }
        #expect(message.contains("No pull request"))
    }

    @Test("attemptLocalMergeForPullRequest fails when another local merge is already running")
    func failsWhenAlreadyRunning() async {
        let vm = Self.makeVM()
        vm.selectedPullRequest = Self.pr()
        vm.pullRequestLocalMergeRunning = true
        let outcome = await vm.attemptLocalMergeForPullRequest()
        guard case .failed(let message) = outcome else {
            Issue.record("Expected .failed, got \(outcome)")
            return
        }
        #expect(message.contains("already running"))
    }

    @Test("attemptLocalMergeForPullRequest fails when a merge or rebase is in progress")
    func failsWhenMergeInProgress() async {
        let vm = Self.makeVM()
        vm.selectedPullRequest = Self.pr()
        vm.mergeState = .merging
        let outcome = await vm.attemptLocalMergeForPullRequest()
        guard case .failed(let message) = outcome else {
            Issue.record("Expected .failed, got \(outcome)")
            return
        }
        #expect(message.contains("merge or rebase"))
        // Guard ran before pullRequestLocalMergeRunning was flipped.
        #expect(vm.pullRequestLocalMergeRunning == false)
    }

    @Test("attemptLocalMergeForPullRequest fails when working tree is dirty")
    func failsWhenDirty() async {
        let vm = Self.makeVM()
        vm.selectedPullRequest = Self.pr()
        let dirty = WorkingCopyFile(
            path: "README.md",
            stagedStatus: .unmodified,
            unstagedStatus: .modified,
            originalPath: nil
        )
        vm.status = WorkingCopyStatus(files: [dirty])
        let outcome = await vm.attemptLocalMergeForPullRequest()
        guard case .failed(let message) = outcome else {
            Issue.record("Expected .failed, got \(outcome)")
            return
        }
        #expect(message.contains("uncommitted"))
        #expect(vm.pullRequestLocalMergeRunning == false)
    }
}

@Suite("RepositoryViewModel — pull request list throttle", .serialized)
@MainActor
struct RepositoryViewModelPullListTests {

    private static func makeVM() -> RepositoryViewModel {
        let url = URL(fileURLWithPath: "/var/empty/gitForge-tests-\(UUID().uuidString)")
        return RepositoryViewModel(repository: Repository(url: url))
    }

    @Test("loadPullRequests short-circuits inside the 30s throttle window when not forced")
    func throttlesUnforced() async {
        let vm = Self.makeVM()
        vm.pullRequestsLastLoadedAt = .now
        // Pre-seed an error so we can detect that the function bailed before
        // touching anything (it would clear `pullRequestsError` on entry).
        vm.pullRequestsError = "sentinel"
        await vm.loadPullRequests()
        #expect(vm.pullRequestsError == "sentinel")
        #expect(vm.pullRequestsLoading == false)
    }

    @Test("loadPullRequests is a no-op when another load is already in flight")
    func noOpWhenAlreadyLoading() async {
        let vm = Self.makeVM()
        vm.pullRequestsLoading = true
        vm.pullRequestsError = "sentinel"
        await vm.loadPullRequests(force: true)
        #expect(vm.pullRequestsError == "sentinel")
        #expect(vm.pullRequestsLoading == true)
    }
}
