import Foundation

/// Identity + global git config snapshot read from `git config --global …`.
nonisolated struct GitIdentity: Sendable, Equatable {
    var name: String?
    var email: String?

    var displayName: String { name ?? "—" }
    var initials: String {
        guard let parts = name?.split(separator: " "), !parts.isEmpty else { return "?" }
        return parts.prefix(2).compactMap { $0.first.map(String.init) }.joined().uppercased()
    }

    static let unknown = GitIdentity(name: nil, email: nil)
}

nonisolated struct GitGlobalConfig: Sendable, Equatable {
    var identity: GitIdentity
    var defaultBranch: String?
    var pullStrategy: String?     // rebase / merge / ff-only
    var signingKey: String?       // user.signingkey
    var autoFetchInterval: Int?   // gitForge.autoFetchInterval (custom key)

    static let unknown = GitGlobalConfig(
        identity: .unknown,
        defaultBranch: nil,
        pullStrategy: nil,
        signingKey: nil,
        autoFetchInterval: nil
    )
}
