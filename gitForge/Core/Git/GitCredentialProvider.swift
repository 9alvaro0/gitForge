import Foundation

/// Signs git network commands with the repo's hosting account (spec §6).
/// `GitCLI` asks it per remote; without one, git uses the system's helpers
/// as it always did.
nonisolated protocol GitCredentialProvider: Sendable {
    /// The account that would sign git requests to this remote, or `nil`
    /// (not HTTPS, no usable account, ambiguous).
    func accountId(remoteURL: String, remoteName: String, repoPath: String) async -> UUID?

    /// Runs `operation` with the remote's credential (`nil` = system
    /// helpers) and handles a refused credential.
    func withCredential<T: Sendable>(remoteURL: String, remoteName: String, repoPath: String,
                                     _ operation: @Sendable (GitCredential?) async throws -> T) async throws -> T
}

/// A git command failed because the server refused the credential of the
/// repo's hosting account.
nonisolated enum GitAccountError: LocalizedError, Equatable, Sendable {
    /// `account`: the login (or the host when it has none).
    case rejected(account: String, host: String)

    var errorDescription: String? {
        switch self {
        case .rejected(let account, let host):
            "\(host) rejected the \(account) account. Reconnect it in Settings › Accounts."
        }
    }
}
