import Foundation

/// Which identity profile is active in a repository, for choosing its
/// hosting account (spec §4.3, step 3). Shared by git credentials and pull
/// requests.
///
/// A clone's destination doesn't exist yet: it uses the profile picked in
/// the clone sheet while the clone runs, or else the global identity.
@MainActor
final class ActiveProfileLookup {
    private let profiles: ProfileStore
    private let identity: @Sendable (URL) async -> RepoIdentity
    private var cloning: [String: UUID] = [:]

    init(profiles: ProfileStore,
         identity: @escaping @Sendable (URL) async -> RepoIdentity = { await GitCLI(workingDirectory: $0).currentIdentity() }) {
        self.profiles = profiles
        self.identity = identity
    }

    /// While a clone into `path` runs, its profile is `profileId`.
    func beginClone(at path: String, profileId: UUID?) {
        cloning[path] = profileId
    }

    func endClone(at path: String) {
        cloning[path] = nil
    }

    func profileId(forRepoAt path: String) async -> UUID? {
        if let pending = cloning[path] { return pending }
        let directory = FileManager.default.fileExists(atPath: path)
            ? URL(fileURLWithPath: path)
            : FileManager.default.homeDirectoryForCurrentUser
        let current = await identity(directory)
        return profiles.match(for: current)?.id
    }
}
