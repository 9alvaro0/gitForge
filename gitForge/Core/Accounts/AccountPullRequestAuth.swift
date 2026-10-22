import Foundation

/// What Pull requests should do for a repo's host (spec §7.4).
nonisolated enum PullRequestAuthResult: Equatable, Sendable {
    case token(String)
    /// No usable credential: offer to connect an account on that instance
    /// (`replacing`: the account to reconnect).
    case connectAccount(instanceId: UUID?, replacing: UUID?)
    /// The user cancelled "Choose an account".
    case cancelled
    /// The token couldn't be obtained (offline, TLS, server down): show it.
    case failed(String)
}

/// The token Pull requests uses for a repo: its hosting account (the same
/// rule as git signing: usable accounts only), refreshed when needed; else
/// "connect".
@MainActor
final class AccountPullRequestAuth {
    private let store: AccountStore
    private let refresher: TokenRefresher
    private let activeProfileId: @Sendable (String) async -> UUID?
    private let chooseAccount: (@Sendable (AmbiguousRemote) async -> RepoAccountChoice?)?

    init(store: AccountStore, refresher: TokenRefresher,
         activeProfileId: @escaping @Sendable (String) async -> UUID? = { _ in nil },
         chooseAccount: (@Sendable (AmbiguousRemote) async -> RepoAccountChoice?)? = nil) {
        self.store = store
        self.refresher = refresher
        self.activeProfileId = activeProfileId
        self.chooseAccount = chooseAccount
    }

    /// The repo's `origin`, recognised against the declared instances.
    func remoteHost(_ cli: GitCLI) async -> RemoteHost? {
        guard let url = await cli.remoteURL("origin") else { return nil }
        return RemoteHost.parse(url, instances: store.instances)
    }

    /// The repo's `origin` host when it isn't declared but looks like
    /// GitHub or GitLab: offered as an instance to add (spec §4.1).
    func suggestedInstance(_ cli: GitCLI) async -> InstanceSuggestion? {
        guard let url = await cli.remoteURL("origin") else { return nil }
        return RemoteHost.suggestedInstance(forRemoteURL: url, instances: store.instances)
    }

    /// `rejected`: the token that just got a 401, to refresh once.
    /// `interactive: false` never shows "Choose an account": several
    /// fitting accounts read as `.cancelled` (background lookups such as a
    /// commit's CI in History).
    func access(host: RemoteHost, repoPath: String, remoteName: String = "origin",
                rejected: String? = nil, interactive: Bool = true) async -> PullRequestAuthResult {
        let instance = store.instance(forHost: host.host)
        let profile = await activeProfileId(repoPath)
        let manual = store.choice(repoPath: repoPath, remoteName: remoteName)
        var resolution = self.resolution(host: host, repoPath: repoPath, remoteName: remoteName, activeProfileId: profile)
        if case .ambiguous(let candidates) = resolution {
            guard interactive else { return .cancelled }
            guard let chooseAccount else { return connect(instanceId: instance?.id) }
            let remote = AmbiguousRemote(repoPath: repoPath, remoteName: remoteName, host: host.host,
                                         ownerRepo: host.slug, candidates: candidates)
            guard let choice = await chooseAccount(remote) else { return .cancelled }
            if manual != .system { store.setChoice(choice, repoPath: repoPath, remoteName: remoteName) }
            resolution = choice.accountId.flatMap { id in candidates.first { $0.id == id } }.map(AccountResolution.account) ?? .none
        }
        guard case .account(let account) = resolution, let instance else {
            return connect(instanceId: instance?.id)
        }
        return await token(for: account, on: instance, rejected: rejected)
    }

    /// The account a repo remote's pull requests use, before anyone is
    /// asked: only the accounts that sign, and a remote set to the system's
    /// credentials for git still gets the account the automatic rules pick
    /// (the API has no "system" credential). The Reviews inbox reads a clone
    /// with it, so it acts as the account the repo's own screen uses.
    func resolution(host: RemoteHost, repoPath: String, remoteName: String = "origin",
                    activeProfileId: UUID?) -> AccountResolution {
        var assignments = store.assignments
        if store.choice(repoPath: repoPath, remoteName: remoteName) == .system { assignments[repoPath]?[remoteName] = nil }
        return AccountResolver.resolve(remoteHost: host.host, remoteOwner: host.owner, repoPath: repoPath,
                                       remoteName: remoteName, activeProfileId: activeProfileId,
                                       instances: store.instances,
                                       accounts: store.accounts.filter(AccountGitCredentials.signs),
                                       assignments: assignments)
    }

    /// The token of a given account, without a repo to resolve it from: the
    /// Reviews inbox follows repositories that may not be on disk, each by
    /// the account that found them. A missing or unusable account reads as
    /// "connect", as for a repo.
    func access(accountId: UUID, rejected: String? = nil) async -> PullRequestAuthResult {
        guard let account = store.accounts.first(where: { $0.id == accountId }),
              let instance = store.instances.first(where: { $0.id == account.instanceId }) else {
            return .connectAccount(instanceId: nil, replacing: nil)
        }
        guard AccountGitCredentials.signs(account) else {
            return .connectAccount(instanceId: instance.id, replacing: account.id)
        }
        return await token(for: account, on: instance, rejected: rejected)
    }

    /// The account's token, refreshed after a rejection (`rejected`); what
    /// can't be fixed here reads as "connect" or, when it may pass, a failure.
    private func token(for account: HostingAccount, on instance: HostingInstance,
                       rejected: String?) async -> PullRequestAuthResult {
        do {
            if let rejected {
                return .token(try await refresher.refreshAfterRejection(for: account, on: instance, rejected: rejected))
            }
            return .token(try await refresher.accessToken(for: account, on: instance))
        } catch HostingAuthError.unauthorized {
            store.markNeedsAttention(account.id, AccountStatusPolicy.rejectionReason(expiresAt: account.expiresAt))
            return .connectAccount(instanceId: instance.id, replacing: account.id)
        } catch HostingAuthError.oauthUnavailable {
            store.markNeedsAttention(account.id, .expired)
            return .connectAccount(instanceId: instance.id, replacing: account.id)
        } catch HostingAuthError.refreshRejected, HostingAuthError.missingSecret {
            return .connectAccount(instanceId: instance.id, replacing: account.id)
        } catch let error as HostingAuthError where Self.isTransient(error) {
            // Offline, TLS, server down: the account may be fine — say what
            // happened instead of asking to connect again.
            return .failed(error.localizedDescription)
        } catch {
            return connect(instanceId: instance.id)
        }
    }

    /// Connect an account on the instance — reconnecting its only failing
    /// account (e.g. a copied token that was rejected) rather than adding another.
    private func connect(instanceId: UUID?) -> PullRequestAuthResult {
        let failing = instanceId.map { id in store.accounts(in: id).filter { !AccountGitCredentials.signs($0) } } ?? []
        return .connectAccount(instanceId: instanceId, replacing: failing.count == 1 ? failing[0].id : nil)
    }

    private static func isTransient(_ error: HostingAuthError) -> Bool {
        switch error {
        case .network, .tls, .server: true
        default: false
        }
    }
}
