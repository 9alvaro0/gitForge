import Foundation

/// What the user chooses to follow in Reviews (R3 Rulings 3 to 7): the
/// patterns, the repos followed by hand and the hidden ones, the limit of 100
/// and the pattern gitForge proposes. The settings themselves and the two
/// methods that write them (`applyConfig`, `storeConfig`) are in
/// `ReviewsStore.swift`, next to the state they change.
extension ReviewsStore {
    /// What one `FollowedRepos.merge` takes besides the user's settings, as
    /// the last refresh worked it out: its clones, the renamed ones under
    /// their current path; the activity; the accounts with their instance, in
    /// store order; and the membership keys. A change of the settings merges
    /// again on it, without the network (Ruling 7).
    nonisolated struct FollowRound: Sendable {
        let local: [LocalRemote]
        let activity: [ActivityCandidate]
        let accounts: [(account: HostingAccount, instance: HostingInstance)]
        let memberKeys: [UUID: Set<String>]
    }

    // MARK: Reading

    /// The repos of every account's membership list that aren't followed nor
    /// hidden, once each, by host and then by path (Ruling 15): what "Add
    /// repository…" offers.
    var followableRepos: [FoundRepo] {
        let skipped = followingKeys
        var found: [FoundRepo] = []
        for shelf in MemberBook(accounts: inboxAccounts, memberships: memberships).shelves {
            for member in shelf.members where !skipped.contains(member.key) {
                found.append(FoundRepo(host: member.host, instanceId: shelf.instance.id, cloneURL: member.cloneURL))
            }
        }
        return found.sorted { lhs, rhs in
            guard lhs.host.host == rhs.host.host else { return lhs.host.host < rhs.host.host }
            return lhs.host.slug.lowercased() < rhs.host.slug.lowercased()
        }
    }

    /// What `pattern` would do, in place of `old` when it replaces one, with
    /// nothing changed (Ruling 6): `adds` counts the members it matches that
    /// aren't followed nor hidden; `total`, the repos followed with it,
    /// counting those the limit would leave out. Before the first refresh
    /// there's no round to merge on, and `total` is what's followed now plus
    /// `adds`.
    func patternCount(_ pattern: FollowPattern, replacing old: FollowPattern?) -> (adds: Int, total: Int) {
        let adds = MemberBook(accounts: inboxAccounts, memberships: memberships).shelf(host: pattern.host)
            .map { additions(of: pattern, on: $0) } ?? 0
        let total = total(with: Self.saving(pattern, replacing: old, in: config))
        return (adds, total ?? repos.count + droppedByLimit + adds)
    }

    // MARK: Changing

    /// Follows `repo` by hand and shows it again if it was hidden (Ruling 5),
    /// unless that takes the inbox over the limit and above what it follows
    /// now (Ruling 6).
    func follow(_ repo: FoundRepo) async -> FollowOutcome {
        let key = FollowedRepos.key(repo.host)
        return await changeChecked { config in
            config.hidden.removeAll { FollowedRepos.key($0) == key }
            if !config.manual.contains(where: { FollowedRepos.key($0) == key }) { config.manual.append(repo.host) }
        }
    }

    /// Drops the manual entry of `host`; another source may still follow it.
    func unfollow(_ host: RemoteHost) async {
        let key = FollowedRepos.key(host)
        guard config.manual.contains(where: { FollowedRepos.key($0) == key }) else { return }
        var next = config
        next.manual.removeAll { FollowedRepos.key($0) == key }
        await applyConfig(next)
    }

    /// Keeps `host` out of the inbox, whatever source finds it, and drops its
    /// manual entry (Ruling 5). The selection and the filter on it go with it.
    func hide(_ host: RemoteHost) async {
        let key = FollowedRepos.key(host)
        guard !config.hidden.contains(where: { FollowedRepos.key($0) == key }) else { return }
        var next = config
        next.manual.removeAll { FollowedRepos.key($0) == key }
        next.hidden.append(host)
        await applyConfig(next)
    }

    /// Lets `host` back in: it shows again if some source still follows it.
    func unhide(_ host: RemoteHost) async {
        let key = FollowedRepos.key(host)
        guard config.hidden.contains(where: { FollowedRepos.key($0) == key }) else { return }
        var next = config
        next.hidden.removeAll { FollowedRepos.key($0) == key }
        await applyConfig(next)
    }

    /// Accepts `pattern`, in place of `old` when editing one, unless that
    /// takes the inbox over the limit and above what it follows now
    /// (Ruling 6): narrowing a pattern goes through even over the limit.
    func savePattern(_ pattern: FollowPattern, replacing old: FollowPattern?) async -> FollowOutcome {
        await changeChecked { config in config = Self.saving(pattern, replacing: old, in: config) }
    }

    func removePattern(_ pattern: FollowPattern) async {
        guard config.patterns.contains(where: { $0.id == pattern.id }) else { return }
        var next = config
        next.patterns.removeAll { $0.id == pattern.id }
        await applyConfig(next)
    }

    /// "Follow" on the proposal (Ruling 3): accepts its pattern and answers
    /// it, unless that takes the inbox over the limit and above what it
    /// follows now, which changes nothing. Without a proposal there's nothing
    /// to do.
    func acceptProposal() async -> FollowOutcome {
        guard let pattern = proposal?.pattern else { return .done }
        return await changeChecked { config in
            config = Self.saving(pattern, replacing: nil, in: config)
            if !config.answeredProposals.contains(pattern.id) { config.answeredProposals.append(pattern.id) }
        }
    }

    /// "Not now" on the proposal (Ruling 3): it doesn't come back, and the
    /// next candidate may take its place.
    func dismissProposal() {
        guard let pattern = proposal?.pattern, !config.answeredProposals.contains(pattern.id) else { return }
        var next = config
        next.answeredProposals.append(pattern.id)
        storeConfig(next)
    }

    // MARK: Working out the repos

    /// The repos followed with `config` on `round`: `FollowedRepos.merge`
    /// with the patterns' and the manual repos as chosen candidates, and the
    /// hidden ones left out (Rulings 4 and 5).
    func followed(in round: FollowRound, with config: ReviewsConfig) -> FollowedSet {
        FollowedRepos.merge(local: round.local, activity: round.activity,
                            chosen: chosenCandidates(config, accounts: round.accounts),
                            hidden: Set(config.hidden.map(FollowedRepos.key)),
                            accounts: Self.signingFirst(round.accounts.map(\.account)),
                            instances: round.accounts.map(\.instance), memberKeys: round.memberKeys)
    }

    /// The repos `config`'s patterns and manual entries choose (Ruling 4),
    /// each with the account and the clone URL `merge` takes. They come from
    /// the membership lists the store keeps, a stale one too: offline, a
    /// pattern's repos stay (Review Focus 4).
    ///
    /// A pattern matches the members of the accounts on the instance of its
    /// host; a manual repo belongs to the instance of its host. One on an
    /// instance without accounts gives nothing.
    func chosenCandidates(_ config: ReviewsConfig,
                          accounts: [(account: HostingAccount, instance: HostingInstance)]) -> [ChosenCandidate] {
        guard !config.patterns.isEmpty || !config.manual.isEmpty else { return [] }
        let book = MemberBook(accounts: accounts, memberships: memberships)
        var candidates: [ChosenCandidate] = []
        var seen: Set<String> = []
        for pattern in config.patterns {
            guard let shelf = book.shelf(host: pattern.host) else { continue }
            for member in shelf.members where pattern.matches(member.host) && seen.insert(member.key).inserted {
                if let candidate = shelf.candidate(for: member.host, source: .pattern) { candidates.append(candidate) }
            }
        }
        seen = []
        for host in config.manual where seen.insert(FollowedRepos.key(host)).inserted {
            guard let shelf = book.shelf(host: host.host) else { continue }
            let current = RemoteHost.make(fullName: host.slug, on: shelf.instance) ?? host
            if let candidate = shelf.candidate(for: current, source: .manual) { candidates.append(candidate) }
        }
        return candidates
    }

    /// The pattern to propose (Rulings 2 and 3): the first instance's, in the
    /// order of the accounts, that has one. Its base is the instance's repos
    /// followed from a clone or by activity (a hidden one isn't followed);
    /// its members, every list of the instance's accounts; and it skips the
    /// patterns accepted and the proposals answered. `nil` before the first
    /// refresh: `total` needs a round to merge on.
    func nextProposal() -> PatternProposal? {
        guard let lastRound else { return nil }
        let following = followingKeys
        let excluding = Set(config.patterns.map(\.id)).union(config.answeredProposals)
        let shelves = MemberBook(accounts: lastRound.accounts, memberships: memberships).shelves
        for shelf in shelves where !shelf.lists.isEmpty {
            let base = repos.filter { repo in
                repo.host.host == shelf.instance.host && !repo.sources.isDisjoint(with: [.local, .activity])
            }
            guard let pattern = PatternInference.propose(base: base.map(\.host), members: shelf.members.map(\.host),
                                                         following: following, excluding: excluding) else { continue }
            let with = followed(in: lastRound, with: Self.saving(pattern, replacing: nil, in: config))
            return PatternProposal(pattern: pattern, adds: additions(of: pattern, on: shelf),
                                   total: with.repos.count + with.dropped)
        }
        return nil
    }

    // MARK: Private

    /// The keys of the repos followed and of the hidden ones.
    private var followingKeys: Set<String> {
        Set(repos.map(\.id)).union(config.hidden.map(FollowedRepos.key))
    }

    /// The members of `shelf` that `pattern` matches and that aren't
    /// followed nor hidden.
    private func additions(of pattern: FollowPattern, on shelf: MemberBook.Shelf) -> Int {
        let following = followingKeys
        return shelf.members.count { pattern.matches($0.host) && !following.contains($0.key) }
    }

    /// `repos.count + dropped` of a merge of `config` on the last round;
    /// `nil` before the first refresh.
    private func total(with config: ReviewsConfig) -> Int? {
        guard let lastRound else { return nil }
        let set = followed(in: lastRound, with: config)
        return set.repos.count + set.dropped
    }

    /// Applies `edit` to the settings unless the inbox would then follow more
    /// than `FollowedRepos.limit` repos and more than it follows now (Ruling
    /// 6, Ruling L), which changes nothing. Both totals are merges on the last
    /// round, with the edited settings and with the current ones. So an inbox
    /// already over the limit can still narrow a pattern, or follow by hand a
    /// repo it follows already: the total stays or drops. An edit that changes
    /// nothing is done at once. Before the first refresh one runs first, so
    /// there's a round to count on; if there's still none (no account, or a
    /// refresh already running), the settings are applied unchecked, and that
    /// refresh merges with them.
    private func changeChecked(_ edit: (inout ReviewsConfig) -> Void) async -> FollowOutcome {
        if lastRound == nil { await refresh(force: true) }
        var next = config
        edit(&next)
        guard next != config else { return .done }
        if let after = total(with: next), after > FollowedRepos.limit, let now = total(with: config), after > now {
            return .overLimit(total: after)
        }
        await applyConfig(next)
        return .done
    }

    /// `config` with `pattern` in `old`'s place, or last when it replaces
    /// none. A pattern already there (by `id`) isn't added twice: it takes
    /// the new spelling.
    private static func saving(_ pattern: FollowPattern, replacing old: FollowPattern?,
                               in config: ReviewsConfig) -> ReviewsConfig {
        var next = config
        var index = next.patterns.count
        if let old, let at = next.patterns.firstIndex(where: { $0.id == old.id }) {
            next.patterns.remove(at: at)
            index = at
        }
        if let existing = next.patterns.firstIndex(where: { $0.id == pattern.id }) {
            next.patterns[existing] = pattern
        } else {
            next.patterns.insert(pattern, at: index)
        }
        return next
    }

    /// The membership lists of the inbox's accounts, by instance, in the
    /// order of the accounts.
    private nonisolated struct MemberBook {
        /// A repo of a membership list.
        struct Member {
            let host: RemoteHost
            /// `FollowedRepos.key(host)`.
            let key: String
            /// The list's HTTPS clone URL.
            let cloneURL: String
        }

        /// One instance's accounts and lists.
        struct Shelf {
            let instance: HostingInstance
            /// Those that sign first, each group in store order.
            let accounts: [HostingAccount]
            /// Each account's list by member key; an account without one has
            /// no entry.
            let lists: [UUID: [String: Member]]
            /// Every list's members once each, in the order of `accounts`.
            let members: [Member]

            /// The candidate for `host` (Ruling 4). It's read with the first
            /// of the instance's accounts whose list has the repo, else with
            /// the first of them: those that sign first, each group in
            /// `FollowedRepos.accountsInPreference` order. A list stale by
            /// more than a day still counts: better than nothing offline. It
            /// takes the list's path and clone URL, else `host` and
            /// `FollowedRepos.cloneURL(for:)`. `nil` without accounts.
            func candidate(for host: RemoteHost, source: FollowSource) -> ChosenCandidate? {
                let key = FollowedRepos.key(host)
                let signing = accounts.filter { AccountGitCredentials.signs($0) }
                let rest = accounts.filter { !AccountGitCredentials.signs($0) }
                let ordered = FollowedRepos.accountsInPreference(for: host, among: signing)
                    + FollowedRepos.accountsInPreference(for: host, among: rest)
                for account in ordered {
                    if let member = lists[account.id]?[key] {
                        return ChosenCandidate(host: member.host, accountId: account.id, source: source,
                                               cloneURL: member.cloneURL)
                    }
                }
                return ordered.first.map { account in
                    ChosenCandidate(host: host, accountId: account.id, source: source,
                                    cloneURL: FollowedRepos.cloneURL(for: host))
                }
            }
        }

        let shelves: [Shelf]

        init(accounts: [(account: HostingAccount, instance: HostingInstance)], memberships: [UUID: MembershipCache]) {
            var instances: [HostingInstance] = []
            var byInstance: [UUID: [HostingAccount]] = [:]
            for (account, instance) in accounts {
                if byInstance[instance.id] == nil { instances.append(instance) }
                byInstance[instance.id, default: []].append(account)
            }
            shelves = instances.map { instance in
                let all = byInstance[instance.id, default: []]
                let ordered = all.filter { AccountGitCredentials.signs($0) }
                    + all.filter { !AccountGitCredentials.signs($0) }
                var lists: [UUID: [String: Member]] = [:]
                var members: [Member] = []
                var seen: Set<String> = []
                for account in ordered {
                    guard let cache = memberships[account.id] else { continue }
                    var list: [String: Member] = [:]
                    for summary in cache.repos {
                        guard let host = RemoteHost.make(fullName: summary.fullName, on: instance) else { continue }
                        let member = Member(host: host, key: FollowedRepos.key(host), cloneURL: summary.httpsURL)
                        if list[member.key] == nil { list[member.key] = member }
                        if seen.insert(member.key).inserted { members.append(member) }
                    }
                    lists[account.id] = list
                }
                return Shelf(instance: instance, accounts: ordered, lists: lists, members: members)
            }
        }

        /// The instance a pattern or a repo of `host` belongs to.
        func shelf(host: String) -> Shelf? {
            shelves.first { $0.instance.host.lowercased() == host.lowercased() }
        }
    }
}
