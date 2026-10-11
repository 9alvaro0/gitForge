import Foundation
import Testing
@testable import gitForge

private final class NoCredentials: GitCredentialProvider, @unchecked Sendable {
    func accountId(remoteURL: String, remoteName: String, repoPath: String) async -> UUID? { nil }
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
}
