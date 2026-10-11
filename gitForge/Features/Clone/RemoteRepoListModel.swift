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
        "\(account.login ?? "Copied token") @ \(instance(of: account)?.host ?? "?")"
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
            state = .idle
        }
    }

    func select(_ accountId: UUID) {
        guard accountId != selectedAccountId, accounts.contains(where: { $0.id == accountId }) else { return }
        reset(selecting: accountId)
    }

    func load() async {
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

    func loadMore() async {
        guard hasMore, !isLoadingMore, state == .loaded,
              let account = selectedAccount, let instance = instance(of: account) else { return }
        let gen = generation
        isLoadingMore = true
        defer { isLoadingMore = false }
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
        selectedAccountId = accountId
        repos = []
        page = 0
        hasMore = false
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

    /// A rejected token marks the account and offers to reconnect it; any
    /// other failure is shown as it is.
    private func handle(_ error: any Error, _ account: HostingAccount) {
        let rejected = (error as? PullRequestFetchError) == .unauthorized
            || (error as? HostingAuthError) == .unauthorized
        if rejected {
            store.markNeedsAttention(account.id, .revoked)
        }
        if rejected || (error as? HostingAuthError) == .refreshRejected {
            repos = []
            hasMore = false
            state = .needsAccount(instanceId: account.instanceId, replacing: account.id)
            return
        }
        state = .failed(error.userMessage)
    }
}
