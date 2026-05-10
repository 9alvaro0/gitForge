import Foundation

extension RepositoryViewModel {
    /// Re-reads `user.name` / `user.email` for this repo. Local override wins
    /// over global; the resulting `RepoIdentity` carries `isLocal` so the
    /// sidebar can badge inherited vs custom identities.
    func refreshIdentity() async {
        repoIdentity = await cli.currentIdentity()
    }

    /// Pins a profile's identity (and signing key) to this repo at `--local`
    /// scope and refreshes the cached snapshot. The matching profile is
    /// resolved from the email next time the sidebar reads the identity.
    func applyProfile(_ profile: GitProfile) async throws {
        try await cli.setLocalIdentity(
            name: profile.userName,
            email: profile.userEmail,
            signingKey: profile.signingKey
        )
        await refreshIdentity()
    }

    /// Drops any `--local` `user.*` overrides so the repo falls back to the
    /// global identity. Caller refreshes — typically used from the sidebar
    /// menu's "Use global identity" entry.
    func clearLocalIdentity() async {
        await cli.clearLocalIdentity()
        await refreshIdentity()
    }
}
