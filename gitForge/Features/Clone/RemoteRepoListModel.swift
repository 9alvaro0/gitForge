import Foundation
import Observation

/// Clone › "My repos" (spec §7.4): the repos one connected account can see,
/// a page at a time, through its instance's API. Lists usable accounts only
/// (the same rule as git signing); with none, offers to connect one.
@MainActor
@Observable
final class RemoteRepoListModel {
    enum State: Equatable {
        /// No usable account of this kind: connect one on `instanceId`,
        /// reconnecting `replacing` when that's the one that failed.
        case needsAccount(instanceId: UUID?, replacing: UUID?)
        case idle
        case loading
        case loaded
        case failed(String)
    }

    static let pageSize = 50

    let kind: HostingInstance.Kind
    private(set) var accounts: [HostingAccount] = []
    private(set) var selectedAccountId: UUID?
    private(set) var repos: [RemoteRepoSummary] = []
    private(set) var state: State = .idle
    private(set) var hasMore = false
    private(set) var isLoadingMore = false
    /// Bumped whenever the list should load from scratch (another account
    /// picked, or the selected one reconnected); the view keys its load on it.
    private(set) var loadRequest: UInt64 = 0
    var search = ""

    @ObservationIgnored private let store: AccountStore
    @ObservationIgnored private let refresher: TokenRefresher
    @ObservationIgnored private let browser: any RemoteRepoBrowsing
    @ObservationIgnored private var page = 0
    /// Bumped by every first-page load and account switch, so a slow answer
    /// for the previous account drops its writes.
    @ObservationIgnored private var generation: UInt64 = 0

    init(kind: HostingInstance.Kind, store: AccountStore, refresher: TokenRefresher,
         browser: (any RemoteRepoBrowsing)? = nil) {
        self.kind = kind
        self.store = store
        self.refresher = refresher
        self.browser = browser ?? RemoteRepoBrowserFactory.make(for: kind)
        refreshAccounts()
    }

    var selectedAccount: HostingAccount? {
        accounts.first { $0.id == selectedAccountId }
    }

    var filtered: [RemoteRepoSummary] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return repos }
        return repos.filter {
            $0.fullName.lowercased().contains(query)
                || $0.name.lowercased().contains(query)
                || ($0.description?.lowercased().contains(query) ?? false)
        }
    }

    /// "login @ host", for the account picker.
    func label(for account: HostingAccount) -> String {
        let login = account.login ?? String(localized: "Copied token")
        return "\(login) @ \(instance(of: account)?.host ?? "?")"
    }

    /// Re-reads the usable accounts of this kind (after connecting one, say),
    /// keeping the selection while it's still there.
    func refreshAccounts() {
        let instanceIds = Set(store.instances.filter { $0.kind == kind }.map(\.id))
        let ofKind = store.accounts.filter { instanceIds.contains($0.instanceId) }
        accounts = ofKind.filter(AccountGitCredentials.signs)
        guard let first = accounts.first else {
            let failing = ofKind.filter { !AccountGitCredentials.signs($0) }
            let builtIn = kind == .github ? HostingInstance.gitHubDotCom.id : HostingInstance.gitLabDotCom.id
            reset(selecting: nil)
            state = failing.count == 1
                ? .needsAccount(instanceId: failing[0].instanceId, replacing: failing[0].id)
                : .needsAccount(instanceId: builtIn, replacing: nil)
            return
        }
        if selectedAccount == nil {
            reset(selecting: first.id)
        } else if case .needsAccount = state {
            // Reconnected in place (same id): load it again.
            state = .idle
            loadRequest &+= 1
        }
    }

    func select(_ accountId: UUID) {
        guard accountId != selectedAccountId, accounts.contains(where: { $0.id == accountId }) else { return }
        reset(selecting: accountId)
    }

    /// Loads the first page. The request runs in the model's own task, so a
    /// cancelled caller (SwiftUI restarting the view's `.task`) doesn't turn
    /// it into a "cancelled" failure; `generation` drops stale answers.
    func load() async {
        await Task { await loadFirstPage() }.value
    }

    func loadMore() async {
        await Task { await loadNextPage() }.value
    }

    private func loadFirstPage() async {
        guard let account = selectedAccount, let instance = instance(of: account) else { return }
        generation &+= 1
        let gen = generation
        state = .loading
        do {
            let chunk = try await fetch(page: 1, account, instance)
            guard gen == generation else { return }
            repos = chunk
            page = 1
            hasMore = chunk.count >= Self.pageSize
            state = .loaded
        } catch {
            guard gen == generation else { return }
            handle(error, account)
        }
    }

    private func loadNextPage() async {
        guard hasMore, !isLoadingMore, state == .loaded,
              let account = selectedAccount, let instance = instance(of: account) else { return }
        let gen = generation
        isLoadingMore = true
        // After an account switch the flag belongs to the new account.
        defer { if gen == generation { isLoadingMore = false } }
        do {
            let chunk = try await fetch(page: page + 1, account, instance)
            guard gen == generation else { return }
            repos.append(contentsOf: chunk)
            page += 1
            hasMore = chunk.count >= Self.pageSize
        } catch {
            guard gen == generation else { return }
            handle(error, account)
        }
    }

    // MARK: Private

    private func instance(of account: HostingAccount) -> HostingInstance? {
        store.instances.first { $0.id == account.instanceId }
    }

    private func reset(selecting accountId: UUID?) {
        generation &+= 1
        loadRequest &+= 1
        selectedAccountId = accountId
        repos = []
        page = 0
        hasMore = false
        isLoadingMore = false
        state = .idle
    }

    /// One page with the account's token; a 401 refreshes a GitLab OAuth
    /// token once and retries.
    private func fetch(page: Int, _ account: HostingAccount, _ instance: HostingInstance) async throws -> [RemoteRepoSummary] {
        let browser = self.browser
        let apiBase = instance.apiBaseURL
        return try await refresher.perform(for: account, on: instance,
                                           retryingWhen: { ($0 as? PullRequestFetchError) == .unauthorized }) { token in
            try await browser.fetchUserRepos(apiBase: apiBase, token: token, page: page)
        }
    }

    /// A rejected token marks the account and offers to reconnect it, as
    /// does a token that can't be read or refreshed; any other failure is
    /// shown as it is.
    private func handle(_ error: any Error, _ account: HostingAccount) {
        let authError = error as? HostingAuthError
        let rejected = (error as? PullRequestFetchError) == .unauthorized || authError == .unauthorized
        if rejected {
            store.markNeedsAttention(account.id, AccountStatusPolicy.rejectionReason(expiresAt: account.expiresAt))
        } else if authError == .oauthUnavailable {
            store.markNeedsAttention(account.id, .expired)
        }
        let reconnect: [HostingAuthError] = [.refreshRejected, .missingSecret, .oauthUnavailable]
        if rejected || authError.map({ reconnect.contains($0) }) == true {
            repos = []
            hasMore = false
            state = .needsAccount(instanceId: account.instanceId, replacing: account.id)
            return
        }
        // The provider's 403 text is about pull requests.
        state = .failed((error as? PullRequestFetchError) == .forbidden
                        ? String(localized: "The account's token isn't allowed to list repositories. Check its scopes.")
                        : error.userMessage)
    }
}
