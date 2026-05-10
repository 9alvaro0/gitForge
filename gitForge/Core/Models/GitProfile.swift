import Foundation

/// A reusable git identity bundle. Users with multiple work contexts
/// (personal vs employer vs client) keep one profile per context and switch
/// the active one per repository — gitForge writes the chosen profile's
/// fields to that repo's local `git config`, never to global.
nonisolated struct GitProfile: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var name: String          // display name e.g. "Personal", "Mercadona"
    var userName: String      // git user.name
    var userEmail: String     // git user.email
    var signingKey: String?

    init(id: UUID = UUID(), name: String, userName: String, userEmail: String, signingKey: String? = nil) {
        self.id = id
        self.name = name
        self.userName = userName
        self.userEmail = userEmail
        self.signingKey = signingKey
    }
}

/// Snapshot of a repository's effective git identity. `name`/`email` are the
/// values git would actually stamp on a commit (local override or inherited
/// from global). `isLocal` is true when the repo has its own `--local`
/// override — the sidebar uses it to badge "Custom" vs "Inherited".
nonisolated struct RepoIdentity: Sendable, Equatable {
    var name: String?
    var email: String?
    var signingKey: String?
    var isLocal: Bool

    static let unknown = RepoIdentity(name: nil, email: nil, signingKey: nil, isLocal: false)
}
