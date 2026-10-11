import Foundation

/// What Pull requests should do for a repo's host (spec §7.4).
nonisolated enum PullRequestAuthResult: Equatable, Sendable {
    case token(String)
    /// No usable credential: offer to connect an account on that instance
    /// (`replacing`: the account to reconnect).
    case connectAccount(instanceId: UUID?, replacing: UUID?)
    /// The user cancelled "Choose an account".
    case cancelled
}

/// The token Pull requests uses for a repo: its hosting account (the same
/// rule as git signing: usable accounts only), refreshed when needed; else
/// the old per-host token (until phase 5b retires it); else "connect".
@MainActor
final class AccountPullRequestAuth {
    private let store: AccountStore
    private let refresher: TokenRefresher
    private let activeProfileId: @Sendable (String) async -> UUID?
    private let chooseAccount: (@Sendable (AmbiguousRemote) async -> RepoAccountChoice?)?
    private let legacyToken: @MainActor (String) -> String?

    init(store: AccountStore, refresher: TokenRefresher,
         activeProfileId: @escaping @Sendable (String) async -> UUID? = { _ in nil },
         chooseAccount: (@Sendable (AmbiguousRemote) async -> RepoAccountChoice?)? = nil,
         legacyToken: @escaping @MainActor (String) -> String? = { RemoteCredentialsStore.shared.token(for: $0) }) {
        self.store = store
        self.refresher = refresher
        self.activeProfileId = activeProfileId
        self.chooseAccount = chooseAccount
        self.legacyToken = legacyToken
    }

    /// The repo's `origin`, recognising declared instances first.
    func remoteHost(_ cli: GitCLI) async -> RemoteHost? {
        guard let url = await cli.remoteURL("origin") else { return nil }
        return RemoteHost.parse(url, instances: store.instances)
    }

    /// `rejected`: the token that just got a 401, to refresh once.
    func access(host: RemoteHost, repoPath: String, remoteName: String = "origin",
                rejected: String? = nil) async -> PullRequestAuthResult {
        let instance = store.instance(forHost: host.host)
        let profile = await activeProfileId(repoPath)
        var resolution = AccountResolver.resolve(remoteHost: host.host, remoteOwner: host.owner, repoPath: repoPath,
                                                 remoteName: remoteName, activeProfileId: profile,
                                                 instances: store.instances,
                                                 accounts: store.accounts.filter(AccountGitCredentials.signs),
                                                 assignments: store.assignments)
        if case .ambiguous(let candidates) = resolution {
            guard let chooseAccount else { return fallback(host, instanceId: instance?.id, rejected: rejected) }
            let remote = AmbiguousRemote(repoPath: repoPath, remoteName: remoteName, host: host.host,
                                         ownerRepo: host.slug, candidates: candidates)
            guard let choice = await chooseAccount(remote) else { return .cancelled }
            store.setChoice(choice, repoPath: repoPath, remoteName: remoteName)
            resolution = choice.accountId.flatMap { id in candidates.first { $0.id == id } }.map(AccountResolution.account) ?? .none
        }
        guard case .account(let account) = resolution, let instance else {
            return fallback(host, instanceId: instance?.id, rejected: rejected)
        }
        do {
            if let rejected {
                return .token(try await refresher.refreshAfterRejection(for: account, on: instance, rejected: rejected))
            }
            return .token(try await refresher.accessToken(for: account, on: instance))
        } catch HostingAuthError.unauthorized {
            store.markNeedsAttention(account.id, .revoked)
            return .connectAccount(instanceId: instance.id, replacing: account.id)
        } catch HostingAuthError.refreshRejected {
            return .connectAccount(instanceId: instance.id, replacing: account.id)
        } catch {
            return fallback(host, instanceId: instance.id, rejected: rejected)
        }
    }

    /// The old per-host token, unless it's the one just rejected.
    private func fallback(_ host: RemoteHost, instanceId: UUID?, rejected: String?) -> PullRequestAuthResult {
        if let legacy = legacyToken(host.host), legacy != rejected { return .token(legacy) }
        return .connectAccount(instanceId: instanceId, replacing: nil)
    }
}
