import Foundation
import Testing
@testable import gitForge

@Suite("AccountsSettingsModel", .serialized)
@MainActor
struct AccountsSettingsModelTests {
    nonisolated static let now = Date(timeIntervalSince1970: 2_000_000_000)
    nonisolated static let day: TimeInterval = 86_400
    nonisolated static let work = HostingInstance(kind: .gitlab, host: "gitlab.example.com")

    private func row(_ account: HostingAccount, copied: Bool = false) -> AccountRowModel {
        let blocks = AccountsSettingsModel.blocks(instances: HostingInstance.builtIns + [Self.work], accounts: [account],
                                                  copiedAccountIds: copied ? [account.id] : [], now: Self.now)
        return blocks.flatMap(\.accounts)[0]
    }

    @Test("This machine: built-ins first, then the self-hosted one; empty instances still listed")
    func machineBlocks() {
        let copied = HostingAccount(instanceId: HostingInstance.gitLabDotCom.id, method: .personalToken, status: .needsAttention(.revoked))
        let blocks = AccountsSettingsModel.blocks(instances: HostingInstance.builtIns + [Self.work],
                                                  accounts: [copied], copiedAccountIds: [copied.id], now: Self.now)
        #expect(blocks.map(\.host) == ["github.com", "gitlab.com", "gitlab.example.com"])
        #expect(blocks.map(\.tag) == ["token only", "token only", "self-hosted · token only"])
        #expect(blocks[0].accounts.isEmpty)
        #expect(blocks[1].accounts[0].title == "Copied token")
        #expect(blocks[1].accounts[0].subtitle == "Personal token · copied from an old token")
        #expect(blocks[1].accounts[0].initials == "?")
    }

    @Test("Instances whose certificate is trusted say so, for Stop trusting")
    func trusted() {
        let blocks = AccountsSettingsModel.blocks(instances: HostingInstance.builtIns + [Self.work], accounts: [],
                                                  copiedAccountIds: [], trustedHosts: ["gitlab.example.com"],
                                                  now: Self.now)
        #expect(blocks.map(\.isTrusted) == [false, false, true])
    }

    @Test("Status text, tone and main action", arguments: [
        (HostingAccount.Status.ok, "OK", AccountRowModel.Tone.ok, AccountRowModel.PrimaryAction?.none),
        (.unverified, "Unverified", .warn, .test),
        (.needsAttention(.revoked), "Rejected", .bad, .reconnect),
        (.needsAttention(.expired), "Expired", .bad, .reconnect),
        (.needsAttention(.unreachable), "Unreachable", .warn, .reconnect),
    ])
    func statuses(status: HostingAccount.Status, text: String, tone: AccountRowModel.Tone, action: AccountRowModel.PrimaryAction?) {
        let r = row(HostingAccount(instanceId: HostingInstance.gitHubDotCom.id, login: "octo", method: .oauth, status: status))
        #expect(r.statusText == text)
        #expect(r.tone == tone)
        #expect(r.primaryAction == action)
    }

    @Test("Expiring soon counts whole days; missing scopes names them")
    func expiryAndScopes() {
        let expiring = row(HostingAccount(instanceId: HostingInstance.gitLabDotCom.id, login: "tanuki", method: .personalToken,
                                          scopes: ["api"], expiresAt: Self.now + 2.5 * Self.day, status: .expiringSoon))
        #expect(expiring.statusText == "Expires in 3 days")
        #expect(expiring.tone == .warn)
        let readOnly = row(HostingAccount(instanceId: HostingInstance.gitLabDotCom.id, login: "tanuki", method: .personalToken,
                                          scopes: ["read_api", "read_user"], status: .needsAttention(.missingScopes)))
        #expect(readOnly.statusText == "Missing scopes: api, write_repository")
    }

    @Test("Subtitle: name, method, scopes, expiry")
    func subtitle() {
        let r = row(HostingAccount(instanceId: HostingInstance.gitHubDotCom.id, login: "octo", displayName: "Octo Cat",
                                   method: .oauth, scopes: ["repo", "read:org", "workflow"], status: .ok))
        #expect(r.title == "octo")
        #expect(r.subtitle == "Octo Cat · OAuth · repo, read:org, workflow")
        #expect(r.initials == "OC")
        let fineGrained = row(HostingAccount(instanceId: HostingInstance.gitHubDotCom.id, login: "octo", method: .personalToken, status: .ok))
        #expect(fineGrained.subtitle == "Personal token · scopes not verifiable")
    }

    @Test("Linking to a profile and setting a self-hosted client id persist; built-ins keep theirs")
    func storeOperations() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gitForge-settings-\(UUID().uuidString)")
        let secrets = InMemoryAccountSecretStore()
        let store = AccountStore(directory: dir, secrets: secrets, clientIds: OAuthClientIDs(gitHub: "gh", gitLab: nil))
        try store.addInstance(Self.work)
        let account = HostingAccount(instanceId: Self.work.id, login: "tanuki", method: .personalToken)
        try store.addAccount(account, secret: AccountSecret(accessToken: "t"))
        let profile = UUID()
        store.linkAccount(account.id, toProfile: profile)
        store.setOAuthClientId("  own-client  ", forInstance: Self.work.id)
        store.setOAuthClientId("hijack", forInstance: HostingInstance.gitHubDotCom.id)

        let reloaded = AccountStore(directory: dir, secrets: secrets, clientIds: OAuthClientIDs(gitHub: "gh", gitLab: nil))
        #expect(reloaded.accounts[0].linkedProfileId == profile)
        #expect(reloaded.instance(forHost: "gitlab.example.com")?.oauthClientId == "own-client")
        #expect(reloaded.instance(forHost: "github.com")?.oauthClientId == "gh")
        reloaded.setOAuthClientId("  ", forInstance: Self.work.id)
        #expect(reloaded.instance(forHost: "gitlab.example.com")?.oauthClientId == nil)
    }
}
