import Foundation
import Testing
@testable import gitForge

@Suite("Repo account choice and accounts.json v2", .serialized)
@MainActor
struct RepoAccountChoiceTests {
    private static func tempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gitForge-choice-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("System credentials resolve to none, before any other rule")
    func systemResolvesToNone() {
        let account = HostingAccount(instanceId: HostingInstance.gitHubDotCom.id, login: "octo", method: .oauth, status: .ok)
        let resolution = AccountResolver.resolve(remoteHost: "github.com", remoteOwner: "octo", repoPath: "/r/app",
                                                 remoteName: "origin", activeProfileId: nil,
                                                 instances: HostingInstance.builtIns, accounts: [account],
                                                 assignments: ["/r/app": ["origin": .system]])
        #expect(resolution == .none)
    }

    @Test("Choices persist, and clearing one removes it")
    func persists() throws {
        let dir = Self.tempDir()
        let secrets = InMemoryAccountSecretStore()
        let store = AccountStore(directory: dir, secrets: secrets, clientIds: .none)
        let account = HostingAccount(instanceId: HostingInstance.gitHubDotCom.id, login: "octo", method: .oauth)
        try store.addAccount(account, secret: AccountSecret(accessToken: "t"))
        store.setChoice(.system, repoPath: "/r/a", remoteName: "origin")
        store.setChoice(.account(account.id), repoPath: "/r/b", remoteName: "origin")

        let reloaded = AccountStore(directory: dir, secrets: secrets, clientIds: .none)
        #expect(reloaded.choice(repoPath: "/r/a", remoteName: "origin") == .system)
        #expect(reloaded.choice(repoPath: "/r/b", remoteName: "origin") == .account(account.id))
        reloaded.setChoice(nil, repoPath: "/r/a", remoteName: "origin")
        #expect(reloaded.assignments["/r/a"] == nil)
    }

    @Test("A v1 file migrates: assignments become account choices, nothing else is lost")
    func migratesV1() throws {
        let dir = Self.tempDir()
        let accountId = UUID(uuidString: "11111111-2222-4333-8444-555555555555")!
        let instanceId = HostingInstance.gitLabDotCom.id.uuidString
        let v1 = """
        {"version":1,"instances":[],"accounts":[{"id":"\(accountId.uuidString)","instanceId":"\(instanceId)","method":"personalToken","scopes":[],"status":{"unverified":{}}}],
         "assignments":{"/r/app":{"origin":"\(accountId.uuidString)"}},"migratedLegacyTokens":true,
         "legacyHostAccounts":{"gitlab.com":"\(accountId.uuidString)"},"detachedLegacyHosts":["git.old.test"]}
        """
        try Data(v1.utf8).write(to: dir.appendingPathComponent("accounts.json"))
        let store = AccountStore(directory: dir, secrets: InMemoryAccountSecretStore(), clientIds: .none)
        #expect(store.choice(repoPath: "/r/app", remoteName: "origin") == .account(accountId))
        #expect(store.accounts.map(\.id) == [accountId])
        #expect(store.legacyHostAccounts == ["gitlab.com": accountId])
        #expect(store.detachedLegacyHosts == ["git.old.test"])
        #expect(store.migratedLegacyTokens)
        // Loading already persists the migration (the migrated flag saves).
        let saved = try String(contentsOf: dir.appendingPathComponent("accounts.json"), encoding: .utf8)
        #expect(saved.contains("\"version\" : 2"))
        let reloaded = AccountStore(directory: dir, secrets: InMemoryAccountSecretStore(), clientIds: .none)
        #expect(reloaded.choice(repoPath: "/r/app", remoteName: "origin") == .account(accountId))
    }

    @Test("Removing an account drops the choices that pointed at it, not the system ones")
    func removeAccountDropsChoices() throws {
        let store = AccountStore(directory: Self.tempDir(), secrets: InMemoryAccountSecretStore(), clientIds: .none)
        let account = HostingAccount(instanceId: HostingInstance.gitHubDotCom.id, login: "octo", method: .oauth)
        try store.addAccount(account, secret: AccountSecret(accessToken: "t"))
        store.setChoice(.account(account.id), repoPath: "/r/a", remoteName: "origin")
        store.setChoice(.system, repoPath: "/r/b", remoteName: "origin")
        store.removeAccount(account.id)
        #expect(store.choice(repoPath: "/r/a", remoteName: "origin") == nil)
        #expect(store.choice(repoPath: "/r/b", remoteName: "origin") == .system)
    }
}
