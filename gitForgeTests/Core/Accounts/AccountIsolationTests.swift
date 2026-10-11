import Foundation
import Security
import Testing
@testable import gitForge

/// The token refresher and the validator use secrets off the main actor.
/// This only compiles while the secret store, the old token source and the
/// account errors are nonisolated.
@Suite("Accounts — usable off the main actor")
struct AccountIsolationTests {
    private struct Legacy: LegacyTokenSource {
        func legacyHosts() throws -> [String] { ["gitlab.com"] }
        func legacyToken(for host: String) throws -> String? { "t" }
    }

    @Test("Secrets, the old token source and the errors work from a detached task")
    func offMain() async throws {
        let store: AccountSecretStore = InMemoryAccountSecretStore()
        let legacy: LegacyTokenSource = Legacy()
        let id = UUID()
        let result = try await Task.detached {
            try store.write(AccountSecret(accessToken: "t"), for: id)
            let messages = [AccountSecretStoreError.keychain(errSecIO).errorDescription,
                            AccountStoreError.unknownInstance.errorDescription]
            return (store.read(id)?.accessToken, try legacy.legacyHosts(), messages.compactMap { $0 }.count)
        }.value
        #expect(result.0 == "t")
        #expect(result.1 == ["gitlab.com"])
        #expect(result.2 == 2)
    }
}
