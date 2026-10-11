import Foundation

/// The app's `GitCredentialProvider` (spec §6): resolves the remote's hosting
/// account (§4.3) and hands git its token. When the server refuses it, a
/// GitLab OAuth account refreshes once and retries; otherwise the account
/// needs attention and the error says which one to reconnect.
///
/// Only accounts that are `ok` or `expiringSoon` sign: an unverified or
/// failing one (e.g. a copied read-only API token) would replace a system
/// helper that works today.
nonisolated final class AccountGitCredentials: GitCredentialProvider {
    private let store: AccountStore
    private let refresher: TokenRefresher
    private let activeProfileId: @Sendable (String) async -> UUID?

    /// `activeProfileId`: the identity profile active in the repo at a path.
    init(store: AccountStore, refresher: TokenRefresher,
         activeProfileId: @escaping @Sendable (String) async -> UUID? = { _ in nil }) {
        self.store = store
        self.refresher = refresher
        self.activeProfileId = activeProfileId
    }

    static func signs(_ account: HostingAccount) -> Bool {
        switch account.status {
        case .ok, .expiringSoon: true
        case .unverified, .needsAttention: false
        }
    }

    func accountId(remoteURL: String, remoteName: String, repoPath: String) async -> UUID? {
        await resolve(remoteURL: remoteURL, remoteName: remoteName, repoPath: repoPath)?.account.id
    }

    func withCredential<T: Sendable>(remoteURL: String, remoteName: String, repoPath: String,
                                     _ operation: @Sendable (GitCredential?) async throws -> T) async throws -> T {
        guard let context = GitCredentialInjection.context(forRemoteURL: remoteURL),
              let resolved = await resolve(remoteURL: remoteURL, remoteName: remoteName, repoPath: repoPath) else {
            return try await operation(nil)
        }
        let (account, instance) = resolved
        let username = GitCredentialInjection.username(for: instance.kind)
        let rejected = GitAccountError.rejected(account: account.login ?? instance.host, host: instance.host)
        do {
            return try await refresher.perform(for: account, on: instance, retryingWhen: GitCredentialInjection.isRejection) { token in
                try await operation(GitCredential(context: context, username: username, password: token, accountId: account.id))
            }
        } catch HostingAuthError.missingSecret {
            // The Keychain didn't give the token: git falls back to the
            // system, as before accounts.
            return try await operation(nil)
        } catch HostingAuthError.refreshRejected {
            // `TokenRefresher` already marked the account expired.
            throw rejected
        } catch let error where GitCredentialInjection.isRejection(error) {
            await store.markNeedsAttention(account.id, .revoked)
            throw rejected
        }
    }

    private func resolve(remoteURL: String, remoteName: String,
                         repoPath: String) async -> (account: HostingAccount, instance: HostingInstance)? {
        guard GitCredentialInjection.context(forRemoteURL: remoteURL) != nil,
              let host = GitCredentialInjection.host(forRemoteURL: remoteURL) else { return nil }
        let owner = GitCredentialInjection.owner(forRemoteURL: remoteURL)
        let profile = await activeProfileId(repoPath)
        let store = self.store
        return await MainActor.run {
            guard case .account(let account) = store.resolveAccount(remoteHost: host, remoteOwner: owner, repoPath: repoPath,
                                                                    remoteName: remoteName, activeProfileId: profile),
                  Self.signs(account),
                  let instance = store.instance(forHost: host) else { return nil }
            return (account, instance)
        }
    }
}
