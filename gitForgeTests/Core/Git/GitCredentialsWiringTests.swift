import Foundation
import Testing
@testable import gitForge

private final class NoCredentials: GitCredentialProvider, @unchecked Sendable {
    func signer(remoteURL: String, remoteName: String, repoPath: String) async -> GitSigner { .none }
    func withCredential<T: Sendable>(remoteURL: String, remoteName: String, repoPath: String,
                                     _ operation: @Sendable (GitCredential?) async throws -> T) async throws -> T {
        try await operation(nil)
    }
}

@Suite("Git credentials wiring")
@MainActor
struct GitCredentialsWiringTests {
    @Test("A repository's git signs with the provider the catalog gives it")
    func viewModelUsesProvider() {
        let provider = NoCredentials()
        let vm = RepositoryViewModel(repository: Repository(url: URL(fileURLWithPath: "/var/empty")), credentials: provider)
        #expect((vm.cli.credentials as? NoCredentials) === provider)
        #expect(RepositoryViewModel(repository: Repository(url: URL(fileURLWithPath: "/var/empty"))).cli.credentials == nil)
    }

    @Test("A repository's pull requests resolve the host through declared instances")
    func pullsUseInstances() async throws {
        let dir = TemporaryDirectories.make("gitForge-wiring")
        let secrets = InMemoryAccountSecretStore()
        let store = AccountStore(directory: dir, secrets: secrets, clientIds: .none)
        try store.addInstance(HostingInstance(kind: .gitlab, host: "git.empresa.com"))
        let auth = AccountPullRequestAuth(store: store, refresher: TokenRefresher(secrets: secrets))
        let repo = try await GitTestRepo.make { try $0.git("remote", "add", "origin", "https://git.empresa.com/group/app.git") }
        let vm = RepositoryViewModel(repository: Repository(url: repo.url), pullRequestAuth: auth)
        await vm.pullRequests.load(force: true)
        #expect(vm.pullRequests.host?.provider == .gitlab)
        #expect(vm.pullRequests.requiresToken)
        #expect(vm.pullRequests.connectInstanceId == store.instance(forHost: "git.empresa.com")?.id)
    }
}
