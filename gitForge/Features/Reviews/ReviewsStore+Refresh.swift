import Foundation

/// The pieces of `ReviewsStore.refresh` that hold no inbox state: the tokens
/// of one load, one read of a repo's pull requests and what its failure
/// means, and the conversions between the hosts' answers and
/// `FollowedRepos.merge`.
extension ReviewsStore {
    /// The tokens of one load: each account's asked for once, renewed at
    /// most once after a 401 (an expired GitLab OAuth token), and noted when
    /// none can be had.
    @MainActor
    final class TokenBook {
        private enum Entry {
            case token(String)
            /// The account must be connected again.
            case reconnect
            /// No token for now (offline, no account chosen); the account may be fine.
            case unavailable
        }

        private let ask: @MainActor (UUID, String?) async -> PullRequestAuthResult
        private var entries: [UUID: Entry] = [:]
        private var renewed: Set<UUID> = []
        /// Accounts that gave a token when first asked.
        private(set) var answered: Set<UUID> = []
        /// Accounts to connect again.
        private(set) var reconnect: Set<UUID> = []

        init(ask: @escaping @MainActor (UUID, String?) async -> PullRequestAuthResult) {
            self.ask = ask
        }

        /// Asks for the account's token, once.
        func prepare(_ accountId: UUID) async {
            guard entries[accountId] == nil else { return }
            if case .token = note(await ask(accountId, nil), for: accountId) { answered.insert(accountId) }
        }

        func current(_ accountId: UUID) -> String? {
            guard case .token(let value) = entries[accountId] else { return nil }
            return value
        }

        func isUnavailable(_ accountId: UUID) -> Bool {
            guard case .unavailable = entries[accountId] else { return false }
            return true
        }

        /// A token to retry with after `rejected` got a 401: the one another
        /// read already renewed, else a fresh one. A second rejection in the
        /// same load means the account must be connected again.
        func renew(_ accountId: UUID, rejected: String) async -> String? {
            guard let current = current(accountId) else { return nil }
            if current != rejected { return current }
            guard renewed.insert(accountId).inserted else {
                reject(accountId)
                return nil
            }
            guard case .token(let fresh) = note(await ask(accountId, rejected), for: accountId) else { return nil }
            return fresh
        }

        /// A renewed token was rejected too.
        func reject(_ accountId: UUID) {
            entries[accountId] = .reconnect
            reconnect.insert(accountId)
        }

        private func note(_ result: PullRequestAuthResult, for accountId: UUID) -> Entry {
            let entry: Entry
            switch result {
            case .token(let value):
                entry = .token(value)
            case .connectAccount:
                entry = .reconnect
                reconnect.insert(accountId)
            case .cancelled, .failed:
                entry = .unavailable
            }
            entries[accountId] = entry
            return entry
        }
    }

    /// One read of a repo's open pull requests, and what came back.
    nonisolated struct PullsRead: Sendable {
        let repo: ReviewRepo
        let token: String
        let isRetry: Bool
        /// Checked against the store's newest read of the repo when it lands.
        let generation: UInt64
        var result: Result<[PullRequest], any Error> = .success([])

        /// Off the main actor, as a task of the read's group.
        func run(with provider: any PullRequestProvider) async -> PullsRead {
            var read = self
            do {
                read.result = .success(try await provider.fetchPulls(host: repo.host, state: .open, token: token))
            } catch {
                read.result = .failure(error)
            }
            return read
        }
    }

    /// What a failed read means for its repo (Ruling 6).
    enum ReadFailure {
        /// 401: renew the token and retry once.
        case rejected
        /// No network or TLS: keep what the repo had, without a message.
        case offline
        /// 403, 404, a response that can't be read, a server error: the repo
        /// loses its pull requests and shows why.
        case failed(String)
    }

    /// What became of a repo in a load, for `lastRefreshFailed`.
    enum ReadOutcome {
        /// The host answered, with pull requests or with an error.
        case answered
        /// No network, or no token for now: the repo keeps what it had.
        case offline
        /// Its account must be connected again: the repo keeps what it had.
        case withheld
    }

    /// `nil` when the read succeeded.
    static func failure(of read: PullsRead) -> ReadFailure? {
        guard case .failure(let error) = read.result else { return nil }
        switch error as? PullRequestFetchError {
        case .unauthorized: return .rejected
        case .forbidden, .notFound, .decoding, .server: return .failed(PullRequestStore.message(for: error))
        case .network, .tls, nil: return .offline
        }
    }

    /// The accounts that sign first, then those that need attention, each in
    /// store order: `merge` gives an instance's repo with no assignment and
    /// no owner's login to its first account (Ruling 4.3), and that must
    /// never be a dead one.
    static func signingFirst(_ accounts: [HostingAccount]) -> [HostingAccount] {
        accounts.filter { AccountGitCredentials.signs($0) } + accounts.filter { !AccountGitCredentials.signs($0) }
    }

    /// Every page of the account's repos, until an empty one or
    /// `membershipPages` (Ruling 3).
    static func allPages(of browser: any RemoteRepoBrowsing, apiBase: URL,
                         token: String) async throws -> [RemoteRepoSummary] {
        var all: [RemoteRepoSummary] = []
        for page in 1...membershipPages {
            let batch = try await browser.fetchUserRepos(apiBase: apiBase, token: token, page: page)
            if batch.isEmpty { break }
            all += batch
        }
        return all
    }

    /// The account's matched activity as candidates for `FollowedRepos.merge`,
    /// cloned from the membership's HTTPS URL.
    static func candidates(_ matches: [(summary: RemoteRepoSummary, at: Date)], on instance: HostingInstance,
                           accountId: UUID) -> [ActivityCandidate] {
        matches.compactMap { match in
            RemoteHost.make(fullName: match.summary.fullName, on: instance).map { host in
                ActivityCandidate(host: host, accountId: accountId, at: match.at, cloneURL: match.summary.httpsURL)
            }
        }
    }

    /// The repos `accountId` followed by activity, kept while its activity
    /// can't be read: a refresh without network, or before the account is
    /// connected again, mustn't empty the inbox (Review Focus 1 and 4).
    static func carriedOver(_ repos: [ReviewRepo], accountId: UUID) -> [ActivityCandidate] {
        repos.filter { $0.accountId == accountId && $0.sources.contains(.activity) }.map { repo in
            ActivityCandidate(host: repo.host, accountId: accountId, at: repo.lastActivity ?? .distantPast,
                              cloneURL: repo.cloneURL)
        }
    }
}
