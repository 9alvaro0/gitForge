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

    /// How the host writes a PR/MR number: `#42` on GitHub, `!42` on GitLab.
    nonisolated func reference(_ number: Int) -> String {
        switch self {
        case .github: "#\(number)"
        case .gitlab: "!\(number)"
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
    /// Parses a git remote URL (SSH or HTTPS) whose host is a declared
    /// instance (spec §4.1): its kind decides the provider and its API base
    /// goes along. Undeclared hosts aren't recognised; see
    /// `suggestedInstance(forRemoteURL:instances:)`.
    ///
    /// Accepted forms:
    ///   - `git@github.com:owner/repo.git`
    ///   - `ssh://git@github.com/owner/repo.git`
    ///   - `https://github.com/owner/repo.git`
    ///   - `https://gitlab.com/group/sub/repo.git` (nested groups for GitLab)
    nonisolated static func parse(_ remoteURL: String, instances: [HostingInstance]) -> RemoteHost? {
        let trimmed = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let pair = extractHostAndPath(trimmed),
              let host = HostingInstance.normalizedHost(pair.0),
              let instance = instances.first(where: { $0.host == host }) else { return nil }
        let provider: RemoteProvider = instance.kind == .github ? .github : .gitlab
        guard var parsed = parse(trimmed, provider: provider) else { return nil }
        parsed.apiBaseURL = instance.apiBaseURL
        return parsed
    }

    /// An undeclared host whose name looks like GitHub or GitLab, offered as
    /// "Add <host> as a <kind> instance…". `nil` for declared hosts.
    nonisolated static func suggestedInstance(forRemoteURL remoteURL: String,
                                              instances: [HostingInstance]) -> InstanceSuggestion? {
        let trimmed = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let pair = extractHostAndPath(trimmed),
              let host = HostingInstance.normalizedHost(pair.0),
              !instances.contains(where: { $0.host == host }),
              let kind = HostingInstance.guessedKind(forHost: host) else { return nil }
        return InstanceSuggestion(host: host, kind: kind)
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
}

/// A remote's host that isn't a declared instance but looks like GitHub or
/// GitLab by name (spec §4.1).
nonisolated struct InstanceSuggestion: Equatable, Sendable {
    let host: String
    let kind: HostingInstance.Kind
}
