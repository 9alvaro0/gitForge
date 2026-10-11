import Foundation

/// Identifies a hosting platform that can serve pull / merge requests.
enum RemoteProvider: String, Sendable, Equatable, CaseIterable {
    case github
    case gitlab

    var label: String {
        switch self {
        case .github: "GitHub"
        case .gitlab: "GitLab"
        }
    }

    /// The user-visible noun for "merge" PR/MR (used in UI strings).
    var pullNoun: String {
        switch self {
        case .github: "Pull request"
        case .gitlab: "Merge request"
        }
    }
}

/// Parsed coordinates of a hosted repository: host (e.g. `github.com` or a
/// self-hosted GitLab), `owner/repo` slug, and the inferred provider.
nonisolated struct RemoteHost: Sendable, Equatable, Identifiable {
    let provider: RemoteProvider
    let host: String
    let owner: String
    let repo: String
    /// The declared instance's API base; `nil` = derived from the host as before.
    var apiBaseURL: URL? = nil

    var id: String { "\(host)/\(owner)/\(repo)" }

    /// Slug used by both APIs as `:owner/:repo`.
    var slug: String { "\(owner)/\(repo)" }

    /// Full HTTPS URL to the repo's web page.
    var webURL: URL? {
        URL(string: "https://\(host)/\(owner)/\(repo)")
    }
}

extension RemoteHost {
    /// Parse a git remote URL (SSH or HTTPS) into a `RemoteHost`. Returns nil
    /// if the URL doesn't belong to a supported provider.
    ///
    /// Accepted forms:
    ///   - `git@github.com:owner/repo.git`
    ///   - `ssh://git@github.com/owner/repo.git`
    ///   - `https://github.com/owner/repo.git`
    ///   - `https://gitlab.com/group/sub/repo.git` (nested groups for GitLab)
    nonisolated static func parse(_ remoteURL: String) -> RemoteHost? {
        let trimmed = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let pair = extractHostAndPath(trimmed), let provider = providerForHost(pair.0) else { return nil }
        return parse(trimmed, provider: provider)
    }

    /// Like `parse(_:)`, but a host declared as an instance (P5 / spec §4.1)
    /// wins over the host-name guess: its kind decides the provider and its
    /// API base goes along. Undeclared hosts fall back to the guess.
    nonisolated static func parse(_ remoteURL: String, instances: [HostingInstance]) -> RemoteHost? {
        let trimmed = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let pair = extractHostAndPath(trimmed),
              let host = HostingInstance.normalizedHost(pair.0),
              let instance = instances.first(where: { $0.host == host }) else {
            return parse(remoteURL)
        }
        let provider: RemoteProvider = instance.kind == .github ? .github : .gitlab
        guard var parsed = parse(trimmed, provider: provider) else { return nil }
        parsed.apiBaseURL = instance.apiBaseURL
        return parsed
    }

    /// The path half of `parse`, once the provider is known.
    private nonisolated static func parse(_ trimmed: String, provider: RemoteProvider) -> RemoteHost? {
        guard !trimmed.isEmpty, let pair = extractHostAndPath(trimmed) else { return nil }
        let (host, path) = pair

        // Strip leading slash + trailing `.git` and split into segments.
        var pathComponents = path
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .components(separatedBy: "/")
            .filter { !$0.isEmpty }
        guard pathComponents.count >= 2 else { return nil }

        if let last = pathComponents.last, last.hasSuffix(".git") {
            pathComponents[pathComponents.count - 1] = String(last.dropLast(4))
        }

        let repo = pathComponents.removeLast()
        // GitHub: exactly one owner. GitLab: groups can be nested → join with `/`.
        let owner: String = {
            switch provider {
            case .github: return pathComponents.last ?? ""
            case .gitlab: return pathComponents.joined(separator: "/")
            }
        }()

        guard !owner.isEmpty, !repo.isEmpty else { return nil }
        // Normalize host to lowercase so save/read keys match regardless of
        // how the user typed the remote URL.
        return RemoteHost(provider: provider, host: host.lowercased(), owner: owner, repo: repo)
    }

    /// Returns `(host, path)` from any of the supported URL forms.
    private nonisolated static func extractHostAndPath(_ url: String) -> (String, String)? {
        // SCP-style: `git@host:owner/repo.git`
        if let atIndex = url.firstIndex(of: "@"),
           let colonIndex = url.firstIndex(of: ":"),
           atIndex < colonIndex,
           !url.lowercased().hasPrefix("http"),
           !url.lowercased().hasPrefix("ssh://") {
            let host = String(url[url.index(after: atIndex)..<colonIndex])
            let path = String(url[url.index(after: colonIndex)...])
            return (host, path)
        }

        // URL-style: `https://...`, `ssh://git@host/...`, `git://host/...`.
        guard let parsed = URL(string: url), let host = parsed.host else { return nil }
        return (host, parsed.path)
    }

    private nonisolated static func providerForHost(_ host: String) -> RemoteProvider? {
        let normalized = host.lowercased()
        if normalized == "github.com" || normalized.hasSuffix(".github.com") {
            return .github
        }
        if normalized == "gitlab.com" || normalized.contains("gitlab") {
            // Self-hosted GitLab is common — match anything containing "gitlab".
            return .gitlab
        }
        return nil
    }
}
