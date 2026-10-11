import Foundation
import Testing
@testable import gitForge

@Suite("AccountGitCredentials", .serialized)
@MainActor
struct AccountGitCredentialsTests {
    nonisolated static let remote = "https://gitlab.com/group/app.git"
    nonisolated static let authFailure = GitError.commandFailed(
        args: ["fetch"], exitCode: 128,
        stderr: "remote: HTTP Basic: Access denied\nfatal: Authentication failed for 'https://gitlab.com/group/app.git/'")

    private struct Setup {
        let store: AccountStore
        let secrets: InMemoryAccountSecretStore
        let provider: AccountGitCredentials
    }

    private func setup(refresh: @escaping @Sendable (String) async throws -> TokenGrant = { _ in throw HostingAuthError.refreshRejected },
                       activeProfileId: @escaping @Sendable (String) async -> UUID? = { _ in nil }) -> Setup {
        let secrets = InMemoryAccountSecretStore()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gitForge-gitcreds-\(UUID().uuidString)")
        let store = AccountStore(directory: dir, secrets: secrets, clientIds: OAuthClientIDs(gitHub: nil, gitLab: "test-client"))
        let client = FakeAuthClient(refresh: refresh)
        let refresher = TokenRefresher(secrets: secrets, makeClient: { _ in client },
                                       onRefreshRejected: { id in await store.markNeedsAttention(id, .expired) })
        return Setup(store: store, secrets: secrets,
                     provider: AccountGitCredentials(store: store, refresher: refresher, activeProfileId: activeProfileId))
    }

    @discardableResult
    private func addAccount(_ store: AccountStore, instance: HostingInstance = .gitLabDotCom, login: String = "tanuki-test",
                            method: HostingAccount.Method = .personalToken, status: HostingAccount.Status = .ok,
                            secret: AccountSecret = AccountSecret(accessToken: "test-pat-value"),
                            linkedProfileId: UUID? = nil) throws -> HostingAccount {
        let account = HostingAccount(instanceId: instance.id, login: login, method: method, status: status,
                                     linkedProfileId: linkedProfileId)
        try store.addAccount(account, secret: secret)
        return account
    }

    private func credential(_ provider: AccountGitCredentials, remote: String = AccountGitCredentialsTests.remote) async throws -> GitCredential? {
        try await provider.withCredential(remoteURL: remote, remoteName: "origin", repoPath: "/r/app") { $0 }
    }

    @Test("An HTTPS remote of the account's instance gets its token as oauth2, scoped to the host")
    func signsGitLab() async throws {
        let s = setup()
        let account = try addAccount(s.store)
        #expect(try await credential(s.provider) == GitCredential(context: "https://gitlab.com", username: "oauth2",
                                                                  password: "test-pat-value", accountId: account.id))
        #expect(await s.provider.accountId(remoteURL: Self.remote, remoteName: "origin", repoPath: "/r/app") == account.id)
    }

    @Test("GitHub signs as x-access-token")
    func signsGitHub() async throws {
        let s = setup()
        try addAccount(s.store, instance: .gitHubDotCom, login: "octo-test")
        #expect(try await credential(s.provider, remote: "https://github.com/octo-test/app.git")?.username == "x-access-token")
    }

    @Test("SSH, scp-style and plain HTTP remotes get nothing",
          arguments: ["git@gitlab.com:group/app.git", "ssh://git@gitlab.com/group/app.git", "http://gitlab.com/group/app.git"])
    func notHTTPS(remote: String) async throws {
        let s = setup()
        try addAccount(s.store)
        #expect(try await credential(s.provider, remote: remote) == nil)
        #expect(await s.provider.accountId(remoteURL: remote, remoteName: "origin", repoPath: "/r/app") == nil)
    }

    @Test("Accounts that aren't ok sign nothing, so the system helper keeps working",
          arguments: [HostingAccount.Status.unverified, .needsAttention(.missingScopes), .needsAttention(.revoked)])
    func unusableAccounts(status: HostingAccount.Status) async throws {
        let s = setup()
        try addAccount(s.store, status: status)
        #expect(try await credential(s.provider) == nil)
        #expect(await s.provider.accountId(remoteURL: Self.remote, remoteName: "origin", repoPath: "/r/app") == nil)
    }

    @Test("expiringSoon still signs")
    func expiringSoonSigns() async throws {
        let s = setup()
        try addAccount(s.store, status: .expiringSoon)
        #expect(try await credential(s.provider) != nil)
    }

    @Test("No account for the host, or several and none chosen: nothing")
    func noneOrAmbiguous() async throws {
        let s = setup()
        #expect(try await credential(s.provider, remote: "https://git.other.test/group/app.git") == nil)
        try addAccount(s.store, login: "first")
        try addAccount(s.store, login: "second")
        #expect(try await credential(s.provider) == nil)
    }

    @Test("The active identity profile's account is the one used")
    func activeProfile() async throws {
        let profile = UUID()
        let s = setup(activeProfileId: { _ in profile })
        try addAccount(s.store, login: "first")
        let linked = try addAccount(s.store, login: "second", secret: AccountSecret(accessToken: "test-linked-value"),
                                    linkedProfileId: profile)
        #expect(try await credential(s.provider)?.accountId == linked.id)
    }

    @Test("A refused token: the account needs attention and the error names it")
    func rejected() async throws {
        let s = setup()
        try addAccount(s.store)
        let attempts = LockedList<String>()
        await #expect(throws: GitAccountError.rejected(account: "tanuki-test", host: "gitlab.com")) {
            try await s.provider.withCredential(remoteURL: Self.remote, remoteName: "origin", repoPath: "/r/app") { credential -> Void in
                attempts.append(credential?.password ?? "none")
                throw Self.authFailure
            }
        }
        #expect(attempts.values == ["test-pat-value"])
        #expect(s.store.accounts[0].status == .needsAttention(.revoked))
    }

    @Test("GitLab OAuth: one refresh, then the retry goes with the new token")
    func oauthRetry() async throws {
        let s = setup(refresh: { _ in TokenGrant(accessToken: "test-new-access", refreshToken: "test-refresh-2", expiresIn: 7200, scopes: nil) })
        try addAccount(s.store, method: .oauth,
                       secret: AccountSecret(accessToken: "test-old-access", refreshToken: "test-refresh-1",
                                             accessTokenExpiresAt: Date().addingTimeInterval(3600)))
        let attempts = LockedList<String>()
        let result = try await s.provider.withCredential(remoteURL: Self.remote, remoteName: "origin", repoPath: "/r/app") { credential -> String in
            attempts.append(credential?.password ?? "none")
            if credential?.password == "test-old-access" { throw Self.authFailure }
            return "pushed"
        }
        #expect(result == "pushed")
        #expect(attempts.values == ["test-old-access", "test-new-access"])
        #expect(s.store.accounts[0].status == .ok)
    }

    @Test("Refresh refused: the account is expired and the error names it")
    func refreshRefused() async throws {
        let s = setup()
        try addAccount(s.store, method: .oauth,
                       secret: AccountSecret(accessToken: "test-old-access", refreshToken: "test-refresh-1",
                                             accessTokenExpiresAt: Date().addingTimeInterval(3600)))
        await #expect(throws: GitAccountError.rejected(account: "tanuki-test", host: "gitlab.com")) {
            try await s.provider.withCredential(remoteURL: Self.remote, remoteName: "origin", repoPath: "/r/app") { _ -> Void in
                throw Self.authFailure
            }
        }
        #expect(s.store.accounts[0].status == .needsAttention(.expired))
    }

    @Test("A 403 (no rights on that repo) is the caller's error, not the account's")
    func forbiddenIsNotRejection() async throws {
        let s = setup()
        try addAccount(s.store)
        let forbidden = GitError.commandFailed(args: ["push"], exitCode: 128,
                                               stderr: "fatal: unable to access 'https://gitlab.com/group/app.git/': The requested URL returned error: 403")
        await #expect(throws: forbidden) {
            try await s.provider.withCredential(remoteURL: Self.remote, remoteName: "origin", repoPath: "/r/app") { _ -> Void in
                throw forbidden
            }
        }
        #expect(s.store.accounts[0].status == .ok)
    }

    @Test("Another host's refusal in the same run (submodule, other remote) isn't the account's")
    func otherHostRefusal() async throws {
        let s = setup()
        try addAccount(s.store)
        let otherHost = GitError.commandFailed(args: ["fetch", "--all"], exitCode: 128,
                                               stderr: "fatal: Authentication failed for 'https://git.other.test/x.git/'")
        await #expect(throws: otherHost) {
            try await s.provider.withCredential(remoteURL: Self.remote, remoteName: "origin", repoPath: "/r/app") { _ -> Void in
                throw otherHost
            }
        }
        #expect(s.store.accounts[0].status == .ok)
    }

    @Test("The token missing from the Keychain: git falls back to the system")
    func missingSecret() async throws {
        let s = setup()
        let account = try addAccount(s.store)
        s.secrets.delete(account.id)
        #expect(try await credential(s.provider) == nil)
    }
}
