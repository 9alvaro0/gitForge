import Foundation

/// A repository path with stars, like `apps/*/android/*`, that the user follows
/// as a family of repos instead of one by one (R3 Ruling 1).
///
/// It belongs to an instance by its host, not by the instance's id, so it
/// survives removing the instance and adding it back. The text is segments
/// separated by `/`; a `*` is exactly one segment and the others are literals
/// that ignore case.
// Hashable, Codable and Identifiable are declared here, not in extensions: with
// the app's MainActor default isolation, Xcode 26 makes an extension's
// conformance main actor-isolated, and the Reviews model needs these off it.
nonisolated struct FollowPattern: Codable, Hashable, Sendable, Identifiable {
    /// `HostingInstance.host` of the instance the pattern applies to.
    let host: String
    /// The path's segments as written; `"*"` stands for any one segment.
    let segments: [String]

    /// The wildcard segment.
    private static let star = "*"

    /// `nil` unless the trimmed text is valid: two segments or more, none
    /// empty, at least one `*` and at least one literal. A `*` stands alone in
    /// its segment, so `pay*` and `**` are refused.
    init?(host: String, text: String) {
        let segments = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "/", omittingEmptySubsequences: false)
            .map(String.init)
        guard segments.count >= 2,
              !segments.contains(""),
              segments.allSatisfy({ !$0.contains(Self.star) || $0 == Self.star }),
              segments.contains(Self.star),
              segments.contains(where: { $0 != Self.star }) else { return nil }
        self.host = host
        self.segments = segments
    }

    /// The segments joined by `/`, as the user wrote them.
    var text: String { segments.joined(separator: "/") }

    /// Two spellings that differ only in case are the same pattern.
    var id: String { "\(host)|\(text.lowercased())" }

    /// Whether `repo.owner/repo.repo` has these segments, with every literal
    /// equal ignoring case. A repo of another host never matches.
    func matches(_ repo: RemoteHost) -> Bool {
        guard repo.host.lowercased() == host.lowercased() else { return false }
        let path = repo.slug.split(separator: "/", omittingEmptySubsequences: false)
        guard path.count == segments.count else { return false }
        return zip(segments, path).allSatisfy { segment, part in
            segment == Self.star || segment.lowercased() == part.lowercased()
        }
    }
}

/// Picks the pattern gitForge proposes from the repos already followed
/// (R3 Ruling 2).
nonisolated enum PatternInference {
    /// Fewest repos of the base a pattern has to cover.
    static let minimumBase = 3

    /// A pattern that would be proposed, and what ranks it.
    private struct Candidate {
        let pattern: FollowPattern
        /// How many repos of the base it covers.
        let covered: Int
        let stars: Int
    }

    /// The best pattern for one instance, or `nil` when none is worth offering.
    ///
    /// - `base`: the instance's repos followed from "In gitForge" or "Activity"
    ///   and not hidden. Their shared shape is what gets inferred.
    /// - `members`: every repo of the instance's membership list. Without it
    ///   there is nothing a pattern could add, so nothing is proposed.
    /// - `following`: the `FollowedRepos.key`s followed or hidden. A pattern has
    ///   to match some member outside them, or it adds nothing.
    /// - `excluding`: `FollowPattern.id`s already accepted or answered.
    ///
    /// A candidate puts a `*` on one or two positions of the path (never all of
    /// them) and a literal on the rest. It needs three repos of the base that
    /// differ in each starred position, and one member to add. The winner
    /// covers the most of the base, then has the fewest stars, then the least
    /// text. Its literals are written as the group's first repo by key writes
    /// them.
    static func propose(base: [RemoteHost], members: [RemoteHost], following: Set<String>,
                        excluding: Set<String>) -> FollowPattern? {
        var seen = Set<String>()
        let repos = base.filter { seen.insert(FollowedRepos.key($0)).inserted }
            .sorted { FollowedRepos.key($0) < FollowedRepos.key($1) }
        guard let host = repos.first?.host, repos.count >= minimumBase else { return nil }
        let addable = members.filter { !following.contains(FollowedRepos.key($0)) }
        guard !addable.isEmpty else { return nil }

        let paths = repos.map { path(of: $0) }
        var candidates: [Candidate] = []
        for (length, ofLength) in Dictionary(grouping: paths, by: \.count) where length >= 2 {
            for stars in starPositions(pathLength: length) {
                let groups = Dictionary(grouping: ofLength) { path in
                    path.indices.filter { !stars.contains($0) }.map { path[$0].lowercased() }
                }
                for group in groups.values where group.count >= minimumBase {
                    // Each star has to stand for at least two different values.
                    guard stars.allSatisfy({ position in
                        Set(group.map { $0[position].lowercased() }).count >= 2
                    }) else { continue }
                    // The group is in key order, so its first is the first repo by key.
                    var segments = group[0]
                    for position in stars { segments[position] = "*" }
                    guard let pattern = FollowPattern(host: host, text: segments.joined(separator: "/")),
                          !excluding.contains(pattern.id),
                          addable.contains(where: pattern.matches) else { continue }
                    candidates.append(Candidate(pattern: pattern, covered: group.count, stars: stars.count))
                }
            }
        }
        return candidates.min { first, second in
            if first.covered != second.covered { return first.covered > second.covered }
            if first.stars != second.stars { return first.stars < second.stars }
            return first.pattern.text.lowercased() < second.pattern.text.lowercased()
        }?.pattern
    }

    /// The segments of `owner/repo`; a GitLab owner can have several.
    private static func path(of repo: RemoteHost) -> [String] {
        repo.slug.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
    }

    /// Every set of one or two positions a path of this length can star, never
    /// all of them.
    private static func starPositions(pathLength: Int) -> [[Int]] {
        var sets = (0..<pathLength).map { [$0] }
        if pathLength > 2 {
            for first in 0..<pathLength {
                for second in (first + 1)..<pathLength { sets.append([first, second]) }
            }
        }
        return sets
    }
}
