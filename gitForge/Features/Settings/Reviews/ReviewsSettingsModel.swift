import Foundation

/// What Settings › Reviews shows, derived from the Reviews store (pure; R3
/// Ruling 15).
nonisolated enum ReviewsSettingsModel {
    /// The order a repo's sources are listed in.
    static let sourceOrder: [FollowSource] = [.local, .activity, .pattern, .manual]

    /// What a repo is removed with: "Stop following" drops the hand-made
    /// entry; "Hide" keeps it out of the inbox whatever finds it.
    enum Removal: Equatable, Sendable { case stopFollowing, hide }

    /// The titles of `sources`, in `sourceOrder`.
    static func sourceTitles(_ sources: Set<FollowSource>) -> [String] {
        sourceOrder.filter(sources.contains).map(\.title)
    }

    /// Followed repos by host (alphabetical), each host's by path; both sort
    /// as Finder sorts names: ignoring case, numbers by value
    /// (`service-2` before `service-10`).
    static func groups(_ repos: [ReviewRepo]) -> [(host: String, repos: [ReviewRepo])] {
        grouped(repos, by: \.host)
    }

    /// The repos "Add repository…" offers, grouped and ordered as `groups`
    /// orders the followed ones.
    static func groups(_ repos: [FoundRepo]) -> [(host: String, repos: [FoundRepo])] {
        grouped(repos, by: \.host)
    }

    /// Only a repo followed by hand and by nothing else stops being followed;
    /// any other one is hidden, or another source would bring it back.
    static func removal(for repo: ReviewRepo) -> Removal {
        repo.sources == [.manual] ? .stopFollowing : .hide
    }

    /// The repos whose path has every word of `query` unbroken
    /// (`FuzzyMatcher.substringMatch`: case and accents ignored), in their
    /// order; words are split on spaces, as ⌘K splits them. A blank query
    /// keeps them all.
    static func filter(_ repos: [FoundRepo], query: String) -> [FoundRepo] {
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return repos }
        return repos.filter { repo in
            words.allSatisfy { FuzzyMatcher.substringMatch($0, in: repo.host.slug) != nil }
        }
    }

    /// The hidden repos by host (alphabetical), then by path, as `groups`
    /// sorts them.
    static func sortedHidden(_ hidden: [RemoteHost]) -> [RemoteHost] {
        hidden.sorted(by: precedes)
    }

    /// How many of `repos` `pattern` matches.
    static func repoCount(of pattern: FollowPattern, in repos: [ReviewRepo]) -> Int {
        repos.count { pattern.matches($0.host) }
    }

    private static func grouped<Repo>(_ repos: [Repo],
                                      by remote: (Repo) -> RemoteHost) -> [(host: String, repos: [Repo])] {
        let byHost = Dictionary(grouping: repos) { remote($0).host }
        return byHost.keys.sorted(by: precedes).map { host in
            (host: host, repos: byHost[host, default: []].sorted { precedes(remote($0), remote($1)) })
        }
    }

    private static func precedes(_ lhs: String, _ rhs: String) -> Bool {
        lhs.localizedStandardCompare(rhs) == .orderedAscending
    }

    private static func precedes(_ lhs: RemoteHost, _ rhs: RemoteHost) -> Bool {
        let byHost = lhs.host.localizedStandardCompare(rhs.host)
        guard byHost == .orderedSame else { return byHost == .orderedAscending }
        return precedes(lhs.slug, rhs.slug)
    }
}

nonisolated extension FollowSource {
    /// How Settings › Reviews names the source.
    var title: String {
        switch self {
        case .local: String(localized: "In gitForge")
        case .activity: String(localized: "Activity")
        case .pattern: String(localized: "Pattern")
        case .manual: String(localized: "Manual")
        }
    }
}
