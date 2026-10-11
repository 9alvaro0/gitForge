import Foundation

/// The username and token git gets for one network command (spec §6), and
/// how: an inline credential helper scoped to the remote's host, fed from
/// two environment variables of that one child process. The token never
/// appears in arguments, URLs or logs.
nonisolated struct GitCredential: Equatable, Sendable {
    /// `https://host[:port]`: the URL the helper is scoped to.
    let context: String
    let username: String
    let password: String
    /// The account it came from; `nil` in tests.
    let accountId: UUID?

    init(context: String, username: String, password: String, accountId: UUID? = nil) {
        self.context = context
        self.username = username
        self.password = password
        self.accountId = accountId
    }

    static let userVariable = "GITFORGE_CRED_USER"
    static let passwordVariable = "GITFORGE_CRED_PASS"

    /// Answers `get` from the environment; `store` and `erase` do nothing.
    static let helperScript = #"!f() { if test "$1" = get; then printf 'username=%s\npassword=%s\n' "$GITFORGE_CRED_USER" "$GITFORGE_CRED_PASS"; fi; }; f"#

    /// `-c` pairs placed before the subcommand. The empty value clears the
    /// helpers configured for this host (osxkeychain…) for this run only;
    /// other hosts keep the user's helpers.
    var configArguments: [String] {
        let key = "credential.\(context).helper"
        return ["-c", "\(key)=", "-c", "\(key)=\(Self.helperScript)"]
    }

    var environment: [String: String] {
        [Self.userVariable: username, Self.passwordVariable: password]
    }
}

/// Pure helpers for signing git with an account (spec §6).
nonisolated enum GitCredentialInjection {
    /// `https://host[:port]` for an HTTPS remote; `nil` for SSH, scp-style,
    /// plain HTTP and local remotes, which never get a token.
    static func context(forRemoteURL url: String) -> String? {
        guard let components = URLComponents(string: url.trimmingCharacters(in: .whitespacesAndNewlines)),
              components.scheme?.lowercased() == "https",
              let host = components.host?.lowercased(), !host.isEmpty else { return nil }
        return components.port.map { "https://\(host):\($0)" } ?? "https://\(host)"
    }

    static func host(forRemoteURL url: String) -> String? {
        URLComponents(string: url.trimmingCharacters(in: .whitespacesAndNewlines))?.host?.lowercased()
    }

    /// First path segment: the owner (GitHub) or top group (GitLab).
    static func owner(forRemoteURL url: String) -> String? {
        URLComponents(string: url.trimmingCharacters(in: .whitespacesAndNewlines))?
            .path.split(separator: "/").first.map(String.init)
    }

    /// GitHub takes any username with a token (`x-access-token` is the
    /// documented one); GitLab wants `oauth2` for OAuth tokens and accepts it
    /// for personal ones.
    static func username(for kind: HostingInstance.Kind) -> String {
        switch kind {
        case .github: "x-access-token"
        case .gitlab: "oauth2"
        }
    }

    /// git's stderr when the server refused the credential (401). A 403 —
    /// usually no permission on that repo — is not a rejection.
    static func isRejection(stderr: String) -> Bool {
        let lower = stderr.lowercased()
        return lower.contains("authentication failed")
            || lower.contains("http basic: access denied")
            || lower.contains("invalid username or token")
            || lower.contains("invalid username or password")
            || lower.contains("error: 401")
    }

    static func isRejection(_ error: any Error) -> Bool {
        guard case GitError.commandFailed(_, _, let stderr)? = error as? GitError else { return false }
        return isRejection(stderr: stderr)
    }
}
