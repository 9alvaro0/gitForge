import Foundation

nonisolated struct GitRef: Sendable, Equatable, Identifiable, Hashable {
    enum Kind: Sendable, Equatable, Hashable {
        case localBranch
        case remoteBranch(remote: String)
        case tag
    }

    let name: String
    let kind: Kind
    let targetSha: String
    let isHead: Bool
    /// Upstream of a local branch, e.g. `origin/main`.
    var upstream: String? = nil
    /// Commits ahead of / behind `upstream`; `nil` without an upstream.
    var ahead: Int? = nil
    var behind: Int? = nil
    /// The upstream is configured but no longer exists on the remote.
    var upstreamGone: Bool = false
    /// Subject of the tip commit (the tag message for annotated tags).
    var subject: String? = nil
    /// Committer date of the tip (tagger date for annotated tags).
    var date: Date? = nil

    var id: String {
        switch kind {
        case .localBranch: "local:\(name)"
        case .remoteBranch(let remote): "remote:\(remote):\(name)"
        case .tag: "tag:\(name)"
        }
    }

    var displayName: String {
        switch kind {
        case .localBranch, .tag:
            return name
        case .remoteBranch(let remote):
            let prefix = "\(remote)/"
            return name.hasPrefix(prefix) ? String(name.dropFirst(prefix.count)) : name
        }
    }

    var isLocalBranch: Bool {
        if case .localBranch = kind { return true } else { return false }
    }

    var isRemoteBranch: Bool {
        if case .remoteBranch = kind { return true } else { return false }
    }

    var isTag: Bool {
        if case .tag = kind { return true } else { return false }
    }
}

/// `%(upstream:track)` output: `[ahead 2, behind 3]`, `[ahead 1]`,
/// `[behind 4]`, `[gone]`, or empty when in sync (or without upstream).
nonisolated struct UpstreamTrack: Equatable, Sendable {
    var ahead = 0
    var behind = 0
    var gone = false

    static func parse(_ raw: String) -> UpstreamTrack {
        var track = UpstreamTrack()
        let body = raw.trimmingCharacters(in: CharacterSet(charactersIn: "[] \t"))
        for part in body.split(separator: ",") {
            let words = part.split(separator: " ")
            guard let key = words.first else { continue }
            switch key {
            case "ahead": track.ahead = words.dropFirst().first.flatMap { Int($0) } ?? 0
            case "behind": track.behind = words.dropFirst().first.flatMap { Int($0) } ?? 0
            case "gone": track.gone = true
            default: break
            }
        }
        return track
    }
}
