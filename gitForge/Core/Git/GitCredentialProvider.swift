import Foundation

/// Signs git network commands with the repo's hosting account (spec §6).
/// `GitCLI` asks it per remote; without one, git uses the system's helpers
/// as it always did.
nonisolated protocol GitCredentialProvider: Sendable {
    /// Who signs git requests to this remote: an account, nobody (system
    /// helpers), or nobody yet because the user must choose (interactive
    /// operations only).
    func signer(remoteURL: String, remoteName: String, repoPath: String) async -> GitSigner

    /// Runs `operation` with the remote's credential (`nil` = system
    /// helpers) and handles a refused credential.
    func withCredential<T: Sendable>(remoteURL: String, remoteName: String, repoPath: String,
                                     _ operation: @Sendable (GitCredential?) async throws -> T) async throws -> T
}

nonisolated enum GitSigner: Equatable, Sendable {
    case none
    case account(UUID)
    case needsChoice
}

/// Marks git work the user didn't start (auto-fetch): it must never stop
/// to ask which account to use (P4 spec §4.2).
nonisolated enum GitNetworkContext {
    @TaskLocal static var isBackground = false
}

/// A remote several accounts could sign; the sheet asks the user once.
nonisolated struct AmbiguousRemote: Equatable, Sendable {
    let repoPath: String
    let remoteName: String
    let host: String
    /// `owner/repo`, for the sheet's text.
    let ownerRepo: String
    let candidates: [HostingAccount]
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
