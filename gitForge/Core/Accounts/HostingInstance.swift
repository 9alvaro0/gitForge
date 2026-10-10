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
        switch kind {
        case .github:
            return URL(string: host == "github.com" ? "https://api.github.com" : "https://\(host)/api/v3")!
        case .gitlab:
            return URL(string: "https://\(host)/api/v4")!
        }
    }

    static let gitHubDotCom = HostingInstance(
        id: UUID(uuidString: "6E0C1B0C-0000-4000-8000-000000000001")!,
        kind: .github, host: "github.com", isBuiltIn: true)

    static let gitLabDotCom = HostingInstance(
        id: UUID(uuidString: "6E0C1B0C-0000-4000-8000-000000000002")!,
        kind: .gitlab, host: "gitlab.com", isBuiltIn: true)

    static let builtIns = [gitHubDotCom, gitLabDotCom]
}
