import Foundation
import Testing
@testable import gitForge

@Suite("AccountStore", .serialized)
@MainActor
struct AccountStoreTests {

    private static func tempDir() -> URL {
        let dir = TemporaryDirectories.make("gitForge-accounts")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("A fresh store has only the built-in instances and no accounts")
    func fresh() {
        let store = AccountStore(directory: Self.tempDir(), secrets: InMemoryAccountSecretStore())
        #expect(store.instances.map(\.host) == ["github.com", "gitlab.com"])
        #expect(store.accounts.isEmpty)
    }

    @Test("Instances, accounts and assignments persist; the secret goes to the secret store, not the file")
    func persists() throws {
        let dir = Self.tempDir()
        let secrets = InMemoryAccountSecretStore()
        let store = AccountStore(directory: dir, secrets: secrets)
        let gitlab = HostingInstance(kind: .gitlab, host: "git.empresa.com")
        try store.addInstance(gitlab)
        let account = HostingAccount(instanceId: gitlab.id, login: "alvaro", method: .personalToken)
        try store.addAccount(account, secret: AccountSecret(accessToken: "glpat-secret"))
        store.assign(account.id, repoPath: "/r/app", remoteName: "origin")

        let file = try String(contentsOf: dir.appendingPathComponent("accounts.json"), encoding: .utf8)
        #expect(!file.contains("glpat-secret"))

        let reloaded = AccountStore(directory: dir, secrets: secrets)
        #expect(reloaded.instance(forHost: "https://GIT.empresa.com/")?.id == gitlab.id)
        #expect(reloaded.accounts(in: gitlab.id).map(\.login) == ["alvaro"])
        #expect(reloaded.assignedAccountId(repoPath: "/r/app", remoteName: "origin") == account.id)
        #expect(reloaded.secret(for: account.id)?.accessToken == "glpat-secret")
    }

    @Test("Adding an instance for a host that already exists fails")
    func duplicateHost() throws {
        let store = AccountStore(directory: Self.tempDir(), secrets: InMemoryAccountSecretStore())
        #expect(throws: AccountStoreError.duplicateHost("github.com")) {
            try store.addInstance(HostingInstance(kind: .github, host: "GitHub.com"))
        }
    }

    @Test("A failed secret write adds no account")
    func failedSecretWrite() {
        let secrets = InMemoryAccountSecretStore()
        secrets.failWrites = true
        let store = AccountStore(directory: Self.tempDir(), secrets: secrets)
        let account = HostingAccount(instanceId: HostingInstance.gitHubDotCom.id, method: .oauth)
        #expect(throws: (any Error).self) { try store.addAccount(account, secret: AccountSecret(accessToken: "t")) }
        #expect(store.accounts.isEmpty)
    }

    @Test("Removing an account drops its secret and its repo assignments")
    func removeAccount() throws {
        let secrets = InMemoryAccountSecretStore()
        let store = AccountStore(directory: Self.tempDir(), secrets: secrets)
        let account = HostingAccount(instanceId: HostingInstance.gitHubDotCom.id, method: .oauth)
        try store.addAccount(account, secret: AccountSecret(accessToken: "t"))
        store.assign(account.id, repoPath: "/r/a", remoteName: "origin")
        store.removeAccount(account.id)
        #expect(store.accounts.isEmpty)
        #expect(secrets.read(account.id) == nil)
        #expect(store.assignedAccountId(repoPath: "/r/a", remoteName: "origin") == nil)
    }

    @Test("Removing an instance removes its accounts; built-ins can't be removed")
    func removeInstance() throws {
        let store = AccountStore(directory: Self.tempDir(), secrets: InMemoryAccountSecretStore())
        let gitlab = HostingInstance(kind: .gitlab, host: "git.empresa.com")
        try store.addInstance(gitlab)
        try store.addAccount(HostingAccount(instanceId: gitlab.id, method: .personalToken), secret: AccountSecret(accessToken: "t"))
        store.removeInstance(gitlab.id)
        store.removeInstance(HostingInstance.gitHubDotCom.id)
        #expect(store.instances.map(\.host) == ["github.com", "gitlab.com"])
        #expect(store.accounts.isEmpty)
    }

    @Test("A corrupt or future-version file is quarantined and the store starts clean")
    func corruptFile() throws {
        for content in ["{not json", #"{"version": 99, "instances": [], "accounts": [], "assignments": {}, "migratedLegacyTokens": false}"#] {
            let dir = Self.tempDir()
            try content.write(to: dir.appendingPathComponent("accounts.json"), atomically: true, encoding: .utf8)
            let store = AccountStore(directory: dir, secrets: InMemoryAccountSecretStore())
            #expect(store.instances.count == 2)
            let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            #expect(names.contains { $0.hasPrefix("accounts.corrupted.") })
        }
    }
}
