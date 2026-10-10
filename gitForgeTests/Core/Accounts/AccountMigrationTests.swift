import Foundation
import Testing
@testable import gitForge

private struct FakeLegacy: LegacyTokenSource {
    var tokens: [String: String]
    func knownHosts() -> [String] { Array(tokens.keys).sorted() }
    func token(for host: String) -> String? { tokens[host] }
}

@Suite("Accounts — copying the old host tokens", .serialized)
@MainActor
struct AccountMigrationTests {

    private static func store(_ secrets: InMemoryAccountSecretStore = .init()) -> AccountStore {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gitForge-mig-\(UUID().uuidString)")
        return AccountStore(directory: dir, secrets: secrets)
    }

    @Test("Each old token becomes an unverified token account on its instance; self-hosted instances are created")
    func copies() {
        let secrets = InMemoryAccountSecretStore()
        let store = Self.store(secrets)
        store.migrateLegacyTokens(from: FakeLegacy(tokens: [
            "github.com": "ghp_1", "gitlab.empresa.com": "glpat_2", "git.unknown.org": "x",
        ]))
        #expect(store.migratedLegacyTokens)
        #expect(store.accounts.count == 2)
        let gitlab = store.instance(forHost: "gitlab.empresa.com")
        #expect(gitlab?.kind == .gitlab)
        #expect(store.instance(forHost: "git.unknown.org") == nil)
        let ghAccount = store.accounts(in: HostingInstance.gitHubDotCom.id).first
        #expect(ghAccount?.method == .personalToken)
        #expect(ghAccount?.status == .unverified)
        #expect(ghAccount.flatMap { secrets.read($0.id) }?.accessToken == "ghp_1")
    }

    @Test("Running it again does nothing")
    func idempotent() {
        let store = Self.store()
        let legacy = FakeLegacy(tokens: ["github.com": "ghp_1"])
        store.migrateLegacyTokens(from: legacy)
        store.migrateLegacyTokens(from: legacy)
        #expect(store.accounts.count == 1)
    }

    @Test("If the Keychain refuses a write, nothing is marked migrated so the next launch retries")
    func retriesAfterFailure() {
        let secrets = InMemoryAccountSecretStore()
        secrets.failWrites = true
        let store = Self.store(secrets)
        store.migrateLegacyTokens(from: FakeLegacy(tokens: ["github.com": "ghp_1"]))
        #expect(!store.migratedLegacyTokens)
        #expect(store.accounts.isEmpty)
        secrets.failWrites = false
        store.migrateLegacyTokens(from: FakeLegacy(tokens: ["github.com": "ghp_1"]))
        #expect(store.migratedLegacyTokens)
        #expect(store.accounts.count == 1)
    }
}
