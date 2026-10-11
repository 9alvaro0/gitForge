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
    /// Asks the user which account an ambiguous remote uses (P4 spec §4.2);
    /// `nil` = never ask (system helper).
    private let chooseAccount: (@Sendable (AmbiguousRemote) async -> RepoAccountChoice?)?

    /// `activeProfileId`: the identity profile active in the repo at a path.
    init(store: AccountStore, refresher: TokenRefresher,
         activeProfileId: @escaping @Sendable (String) async -> UUID? = { _ in nil },
         chooseAccount: (@Sendable (AmbiguousRemote) async -> RepoAccountChoice?)? = nil) {
        self.store = store
        self.refresher = refresher
        self.activeProfileId = activeProfileId
        self.chooseAccount = chooseAccount
    }

    static func signs(_ account: HostingAccount) -> Bool {
        switch account.status {
        case .ok, .expiringSoon: true
        case .unverified, .needsAttention: false
        }
    }

    private enum Resolution {
        case sign(HostingAccount, HostingInstance)
        case ask(AmbiguousRemote, HostingInstance)
        case system
    }

    func signer(remoteURL: String, remoteName: String, repoPath: String) async -> GitSigner {
        switch await resolve(remoteURL: remoteURL, remoteName: remoteName, repoPath: repoPath) {
        case .sign(let account, _): .account(account.id)
        case .ask: .needsChoice
        case .system: .none
        }
    }

    func withCredential<T: Sendable>(remoteURL: String, remoteName: String, repoPath: String,
                                     _ operation: @Sendable (GitCredential?) async throws -> T) async throws -> T {
        guard let context = GitCredentialInjection.context(forRemoteURL: remoteURL) else { return try await operation(nil) }
        let (account, instance): (HostingAccount, HostingInstance)
        switch await resolve(remoteURL: remoteURL, remoteName: remoteName, repoPath: repoPath) {
        case .system:
            return try await operation(nil)
        case .sign(let resolved, let resolvedInstance):
            (account, instance) = (resolved, resolvedInstance)
        case .ask(let ambiguous, let resolvedInstance):
            guard let chooseAccount, let choice = await chooseAccount(ambiguous) else { throw CancellationError() }
            await store.setChoice(choice, repoPath: repoPath, remoteName: remoteName)
            guard case .account(let id) = choice, let chosen = ambiguous.candidates.first(where: { $0.id == id }) else {
                return try await operation(nil)
            }
            (account, instance) = (chosen, resolvedInstance)
        }
        let username = GitCredentialInjection.username(for: instance.kind)
        let rejected = GitAccountError.rejected(account: account.login ?? instance.host, host: instance.host)
        do {
            return try await refresher.perform(for: account, on: instance,
                                               retryingWhen: { GitCredentialInjection.isRejection($0, context: context) }) { token in
                try await operation(GitCredential(context: context, username: username, password: token, accountId: account.id))
            }
        } catch HostingAuthError.missingSecret {
            return try await operation(nil)
        } catch HostingAuthError.refreshRejected {
            throw rejected
        } catch let error where GitCredentialInjection.isRejection(error, context: context) {
            await store.markNeedsAttention(account.id, .revoked)
            throw rejected
        }
    }

    private func resolve(remoteURL: String, remoteName: String, repoPath: String) async -> Resolution {
        guard GitCredentialInjection.context(forRemoteURL: remoteURL) != nil,
              let host = GitCredentialInjection.host(forRemoteURL: remoteURL) else { return .system }
        let owner = GitCredentialInjection.owner(forRemoteURL: remoteURL)
        let profile = await activeProfileId(repoPath)
        let canAsk = chooseAccount != nil && !GitNetworkContext.isBackground
        let store = self.store
        return await MainActor.run {
            guard let instance = store.instance(forHost: host) else { return .system }
            // Only accounts that can sign take part, so a failing copy neither
            // makes a good account ambiguous nor wins by profile link or
            // choice — the same rule as the profile menu.
            switch AccountResolver.resolve(remoteHost: host, remoteOwner: owner, repoPath: repoPath,
                                           remoteName: remoteName, activeProfileId: profile,
                                           instances: store.instances, accounts: store.accounts.filter(Self.signs),
                                           assignments: store.assignments) {
            case .account(let account):
                return .sign(account, instance)
            case .ambiguous(let usable):
                guard canAsk else { return .system }
                let path = URLComponents(string: remoteURL)?.path ?? ""
                let ownerRepo = path.split(separator: "/").joined(separator: "/")
                    .replacingOccurrences(of: ".git", with: "", options: [.anchored, .backwards])
                return .ask(AmbiguousRemote(repoPath: repoPath, remoteName: remoteName, host: host,
                                            ownerRepo: ownerRepo, candidates: usable), instance)
            case .none:
                return .system
            }
        }
    }
}
