import Foundation

/// Following a clone whose repo was renamed or moved (R3 Ruling 10): which
/// clones a refresh asks the host about, the lookups themselves, and the
/// clones as `FollowedRepos.merge` takes them afterwards. The answers live in
/// `ReviewsStore.lookups`, saved with the snapshot.
extension ReviewsStore {
    /// A clone whose current path is asked for: its `FollowedRepos.key`, the
    /// path its `origin` has, and the account and kind of host to ask with.
    nonisolated struct RenameTarget: Equatable, Sendable {
        let key: String
        let host: RemoteHost
        let kind: HostingInstance.Kind
        let accountId: UUID
    }

    /// One `HostSearching.currentPath` call, and what came back.
    nonisolated struct PathRead: Sendable {
        let target: RenameTarget
        let token: String
        let isRetry: Bool
        var result: Result<String?, any Error> = .success(nil)

        /// Off the main actor, as a task of the lookups' group.
        func run(with search: any HostSearching) async -> PathRead {
            var read = self
            do {
                read.result = .success(try await search.currentPath(of: target.host, token: token))
            } catch {
                read.result = .failure(error)
            }
            return read
        }
    }

    /// The clones to ask about this round, in `local` order, one per repo and
    /// at most `renameLookups`; the rest wait for the next round.
    ///
    /// A clone may have been renamed when its instance's membership is known
    /// (`memberKeys`), doesn't list it, and nothing in `vouched` keeps it (the
    /// keys `merge` keeps a clone for whatever the membership says). It's asked
    /// about when it has no lookup in `lookups`, or one older than
    /// `membershipTTL`; with `rereadLists`, whatever its lookup's age. It's
    /// asked with the first of its instance's accounts that sign, in
    /// `FollowedRepos.accountsInPreference` order.
    static func renameTargets(_ local: [LocalRemote], accounts: [(account: HostingAccount, instance: HostingInstance)],
                              memberKeys: [UUID: Set<String>], vouched: Set<String>, lookups: [String: RepoLookup],
                              now: Date, rereadLists: Bool) -> [RenameTarget] {
        var targets: [RenameTarget] = []
        var seen: Set<String> = []
        for remote in local {
            guard targets.count < renameLookups else { break }
            let key = FollowedRepos.key(remote.host)
            guard seen.insert(key).inserted,
                  let instance = accounts.first(where: { $0.instance.host == remote.host.host })?.instance,
                  let members = memberKeys[instance.id], !members.contains(key), !vouched.contains(key) else {
                continue
            }
            if !rereadLists, let cached = lookups[key], now.timeIntervalSince(cached.fetchedAt) < membershipTTL {
                continue
            }
            let signing = accounts
                .filter { $0.instance.id == instance.id && AccountGitCredentials.signs($0.account) }
                .map(\.account)
            guard let account = FollowedRepos.accountsInPreference(for: remote.host, among: signing).first else {
                continue
            }
            targets.append(RenameTarget(key: key, host: remote.host, kind: instance.kind, accountId: account.id))
        }
        return targets
    }

    /// Asks where each target lives now, `concurrency` at a time, with its
    /// account's token; a 401 renews the token once and retries, as
    /// `readPulls` does. Only answers come back, by key: the current path, or
    /// `nil` for a 404. A target with no token, or whose lookup failed any
    /// other way (403, a server that's down, no network), is left out, so the
    /// next round asks again.
    static func lookUpPaths(_ targets: [RenameTarget], tokens: TokenBook,
                            makeSearch: @MainActor (HostingInstance.Kind) -> any HostSearching)
        async -> [String: String?] {
        var found: [String: String?] = [:]
        var pending = targets[...]
        await withTaskGroup(of: PathRead.self) { group in
            var running = 0
            while true {
                while running < concurrency, !Task.isCancelled, let target = pending.popFirst() {
                    guard let token = tokens.current(target.accountId) else { continue }
                    let read = PathRead(target: target, token: token, isRetry: false)
                    let search = makeSearch(target.kind)
                    group.addTask { await read.run(with: search) }
                    running += 1
                }
                guard let read = await group.next() else { break }
                running -= 1
                switch read.result {
                case .success(let path):
                    found.updateValue(path, forKey: read.target.key)
                case .failure(let error as PullRequestFetchError) where error == .unauthorized:
                    let accountId = read.target.accountId
                    guard !read.isRetry else {
                        // The renewed token was rejected too.
                        tokens.reject(accountId)
                        continue
                    }
                    guard !Task.isCancelled, let fresh = await tokens.renew(accountId, rejected: read.token) else {
                        continue
                    }
                    let retry = PathRead(target: read.target, token: fresh, isRetry: true)
                    let search = makeSearch(read.target.kind)
                    group.addTask { await retry.run(with: search) }
                    running += 1
                case .failure:
                    continue
                }
            }
        }
        return found
    }

    /// `local` as `merge` takes it. A clone the membership leaves out, which
    /// nothing in `vouched` keeps, is followed under the path its lookup
    /// found when that is another repo its instance's accounts belong to; its
    /// `outdatedOrigin` is then the path its `origin` still has. Any other
    /// clone stays as it is, and `merge` leaves it out as before. A lookup
    /// older than the day still counts: it's only replaced by a newer answer,
    /// so a lookup that couldn't be made again doesn't drop the clone.
    static func renamed(_ local: [LocalRemote], instances: [HostingInstance], memberKeys: [UUID: Set<String>],
                        vouched: Set<String>, lookups: [String: RepoLookup]) -> [LocalRemote] {
        local.map { remote in
            let key = FollowedRepos.key(remote.host)
            guard let instance = instances.first(where: { $0.host == remote.host.host }),
                  let members = memberKeys[instance.id], !members.contains(key), !vouched.contains(key),
                  let path = lookups[key]?.currentPath,
                  let current = RemoteHost.make(fullName: path, on: instance) else { return remote }
            let currentKey = FollowedRepos.key(current)
            guard currentKey != key, members.contains(currentKey) else { return remote }
            return LocalRemote(host: current, repository: remote.repository,
                               assignedAccountId: remote.assignedAccountId, waitingAccountId: remote.waitingAccountId,
                               outdatedOrigin: remote.host)
        }
    }
}
