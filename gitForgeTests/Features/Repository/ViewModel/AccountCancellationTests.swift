import Foundation
import Testing
@testable import gitForge

/// Signs every remote with an account whose "Choose an account" sheet the
/// user cancels.
private final class CancellingCredentials: GitCredentialProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var calls: Int { lock.withLock { count } }

    func signer(remoteURL: String, remoteName: String, repoPath: String) async -> GitSigner { .account(UUID()) }

    func withCredential<T: Sendable>(remoteURL: String, remoteName: String, repoPath: String,
                                     _ operation: @Sendable (GitCredential?) async throws -> T) async throws -> T {
        lock.withLock { count += 1 }
        throw CancellationError()
    }
}

@Suite("Cancelling the account sheet", .serialized)
@MainActor
struct AccountCancellationTests {
    private func makeVM() async throws -> (RepositoryViewModel, CancellingCredentials) {
        let origin = try await GitTestRepo.make(bare: true)
        let work = try await GitTestRepo.make { repo in
            try repo.commit("first")
            try repo.git("remote", "add", "origin", origin.url.path)
        }
        let credentials = CancellingCredentials()
        return (RepositoryViewModel(repository: Repository(url: work.url), credentials: credentials), credentials)
    }

    @Test("Integrating a PR: cancelling the sheet is a cancel, not a failure")
    func localMergeCancelled() async throws {
        let (vm, _) = try await makeVM()
        vm.pullRequests.selected = PullRequest(id: "1", number: 1, title: "PR", state: .open, authorLogin: nil,
                                               authorAvatarURL: nil, sourceBranch: "feature/1", targetBranch: "main",
                                               webURL: nil, createdAt: nil, updatedAt: nil)
        #expect(await vm.attemptLocalMergeForPullRequest() == .cancelled)
    }

    @Test("Force push with lease: one Cancel stops it, without asking again")
    func forcePushCancelled() async throws {
        let (vm, credentials) = try await makeVM()
        #expect(await vm.push(forceWithLease: true) == false)
        #expect(credentials.calls == 1)
        #expect(vm.remoteFailure == .cancelled)
    }
}
