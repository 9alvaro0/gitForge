import Foundation

/// One server gitForge can talk to: github.com, gitlab.com, or a
/// self-hosted GitHub Enterprise / GitLab instance the user declared.
nonisolated struct HostingInstance: Codable, Identifiable, Hashable, Sendable {
    enum Kind: String, Codable, CaseIterable, Sendable {
        case github, gitlab

        var label: String {
            switch self {
            case .github: "GitHub"
            case .gitlab: "GitLab"
            }
        }
    }

    var id: UUID
    var kind: Kind
    /// Lowercased, no scheme / port / path / `www.`.
    var host: String
    var apiBaseURL: URL
    /// OAuth app registered on this instance; `nil` = token sign-in only.
    var oauthClientId: String?
    /// github.com and gitlab.com: always present, can't be removed.
    var isBuiltIn: Bool

    init(id: UUID = UUID(), kind: Kind, host: String, apiBaseURL: URL? = nil,
         oauthClientId: String? = nil, isBuiltIn: Bool = false) {
        let normalized = Self.normalizedHost(host) ?? host.lowercased()
        self.id = id
        self.kind = kind
        self.host = normalized
        self.apiBaseURL = apiBaseURL ?? Self.defaultAPIBaseURL(kind: kind, host: normalized)
        self.oauthClientId = oauthClientId
        self.isBuiltIn = isBuiltIn
    }

    /// `https://GitLab.Empresa.com:443/x` → `gitlab.empresa.com`. `nil` when
    /// there's no host in the input.
    static func normalizedHost(_ input: String) -> String? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !text.isEmpty else { return nil }
        if !text.contains("://") { text = "https://" + text }
        guard let host = URLComponents(string: text)?.host, !host.isEmpty else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    static func defaultAPIBaseURL(kind: Kind, host: String) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        switch kind {
        case .github where host == "github.com":
            components.host = "api.github.com"
        case .github:
            components.host = host
            components.path = "/api/v3"
        case .gitlab:
            components.host = host
            components.path = "/api/v4"
        }
        // Only reachable with a host `make` would have refused.
        return components.url ?? URL(fileURLWithPath: "/")
    }

    /// `https://<host>`: where the OAuth endpoints live (not the API base).
    var webBaseURL: URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        return components.url ?? apiBaseURL
    }

    static let gitHubDotCom = HostingInstance(
        id: UUID(uuidString: "6E0C1B0C-0000-4000-8000-000000000001")!,
        kind: .github, host: "github.com", isBuiltIn: true)

    static let gitLabDotCom = HostingInstance(
        id: UUID(uuidString: "6E0C1B0C-0000-4000-8000-000000000002")!,
        kind: .gitlab, host: "gitlab.com", isBuiltIn: true)

    static let builtIns = [gitHubDotCom, gitLabDotCom]
}

/// Why "Add instance" can't use what was typed.
nonisolated enum InstanceInputError: LocalizedError, Equatable, Sendable {
    case missingHost
    case invalidHost(String)
    case invalidAPIURL(String)

    var errorDescription: String? {
        switch self {
        case .missingHost: "Enter the instance's address, like https://git.example.com."
        case .invalidHost(let host): "“\(host)” isn't a valid host name."
        case .invalidAPIURL(let url): "“\(url)” isn't a valid HTTPS API address."
        }
    }
}

extension HostingInstance {
    /// A validated instance from what the user typed in "Add instance"
    /// (P4 spec §4.3): host normalised, trailing dot dropped, only DNS
    /// characters; an API URL override must be HTTPS.
    nonisolated static func make(kind: Kind, url: String,
                                 apiBaseURL: String? = nil) -> Result<HostingInstance, InstanceInputError> {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.missingHost) }
        guard var host = normalizedHost(trimmed) else { return .failure(.invalidHost(trimmed)) }
        while host.hasSuffix(".") { host.removeLast() }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789.-")
        guard !host.isEmpty, host.unicodeScalars.allSatisfy(allowed.contains),
              !host.hasPrefix("."), !host.hasPrefix("-"), !host.contains("..") else {
            return .failure(.invalidHost(trimmed))
        }
        var api: URL?
        if let raw = apiBaseURL?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
            guard let parsed = URL(string: raw), parsed.scheme?.lowercased() == "https", parsed.host != nil else {
                return .failure(.invalidAPIURL(raw))
            }
            api = parsed
        }
        return .success(HostingInstance(kind: kind, host: host, apiBaseURL: api))
    }
}
