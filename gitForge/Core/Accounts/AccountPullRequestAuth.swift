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
        // The API has no "system" credential: a remote set to the system's
        // for git still uses the account the automatic rules pick here.
        let manual = store.choice(repoPath: repoPath, remoteName: remoteName)
        var assignments = store.assignments
        if manual == .system { assignments[repoPath]?[remoteName] = nil }
        var resolution = AccountResolver.resolve(remoteHost: host.host, remoteOwner: host.owner, repoPath: repoPath,
                                                 remoteName: remoteName, activeProfileId: profile,
                                                 instances: store.instances,
                                                 accounts: store.accounts.filter(AccountGitCredentials.signs),
                                                 assignments: assignments)
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
