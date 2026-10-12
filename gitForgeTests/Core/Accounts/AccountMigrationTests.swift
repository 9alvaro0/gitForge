import Foundation
import Testing
@testable import gitForge

private struct FakeLegacy: LegacyTokenSource {
    struct ReadFailed: Error {}
    var tokens: [String: String]
    var failList = false
    var failHosts: Set<String> = []
    func legacyHosts() throws -> [String] {
        if failList { throw ReadFailed() }
        return Array(tokens.keys).sorted()
    }
    func legacyToken(for host: String) throws -> String? {
        if failHosts.contains(host) { throw ReadFailed() }
        return tokens[host]
    }
}

@Suite("Accounts — copying the old host tokens", .serialized)
@MainActor
struct AccountMigrationTests {

    private static func store(_ secrets: InMemoryAccountSecretStore = .init()) -> AccountStore {
        let dir = TemporaryDirectories.make("gitForge-mig")
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

    @Test("A failed read of the old store (e.g. access denied) doesn't count as migrated")
    func readFailureRetries() {
        let store = Self.store()
        store.migrateLegacyTokens(from: FakeLegacy(tokens: ["github.com": "ghp_1"], failHosts: ["github.com"]))
        #expect(!store.migratedLegacyTokens)
        #expect(store.accounts.isEmpty)
        store.migrateLegacyTokens(from: FakeLegacy(tokens: ["github.com": "ghp_1"], failList: true))
        #expect(!store.migratedLegacyTokens)
        store.migrateLegacyTokens(from: FakeLegacy(tokens: ["github.com": "ghp_1"]))
        #expect(store.migratedLegacyTokens)
        #expect(store.accounts.count == 1)
    }

    @Test("Runs every launch: a token added or rotated in the old store later is synced, without duplicates")
    func keepsSyncing() {
        let secrets = InMemoryAccountSecretStore()
        let store = Self.store(secrets)
        store.migrateLegacyTokens(from: FakeLegacy(tokens: ["github.com": "ghp_1"]))
        store.migrateLegacyTokens(from: FakeLegacy(tokens: ["github.com": "ghp_2", "gitlab.com": "glpat_9"]))
        #expect(store.accounts.count == 2)
        let gh = store.accounts(in: HostingInstance.gitHubDotCom.id)
        #expect(gh.count == 1)
        #expect(gh.first.flatMap { secrets.read($0.id) }?.accessToken == "ghp_2")
        #expect(store.accounts(in: HostingInstance.gitLabDotCom.id).count == 1)
    }

    @Test("Accounts copied before the host map existed are adopted, not duplicated")
    func adoptsEarlierCopies() throws {
        let secrets = InMemoryAccountSecretStore()
        let store = Self.store(secrets)
        // A copy made by the first version: an unverified token account, no host map entry.
        try store.addAccount(HostingAccount(instanceId: HostingInstance.gitLabDotCom.id, method: .personalToken),
                             secret: AccountSecret(accessToken: "glpat_1"))
        store.migrateLegacyTokens(from: FakeLegacy(tokens: ["gitlab.com": "glpat_1"]))
        #expect(store.accounts.count == 1)
        #expect(store.legacyHostAccounts["gitlab.com"] == store.accounts.first?.id)
    }
}
