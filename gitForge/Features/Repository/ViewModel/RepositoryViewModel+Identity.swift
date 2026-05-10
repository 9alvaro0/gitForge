import Foundation

extension RepositoryViewModel {
    /// Re-reads `user.name` / `user.email` for this repo. Local override wins
    /// over global; the resulting `RepoIdentity` carries `isLocal` so the
    /// sidebar can badge inherited vs custom identities.
    ///
    /// Gen-token guarded so two overlapping refreshes (watcher tick crossing
    /// an explicit refresh, etc.) can't have the slower one stomp the
    /// fresher snapshot.
    func refreshIdentity() async {
        identityGen &+= 1
        let gen = identityGen
        let snapshot = await cli.currentIdentity()
        guard gen == identityGen else { return }
        repoIdentity = snapshot
    }

    /// Pins a profile's identity (and signing key) to this repo at `--local`
    /// scope and refreshes the cached snapshot. The matching profile is
    /// resolved from the email next time the sidebar reads the identity.
    ///
    /// Refresh runs in both success and failure paths so a half-applied
    /// write (e.g. exception between `user.name` and `user.email`) still
    /// leaves the cache mirroring on-disk state.
    func applyProfile(_ profile: GitProfile) async throws {
        do {
            try await cli.setLocalIdentity(
                name: profile.userName,
                email: profile.userEmail,
                signingKey: profile.signingKey
            )
            await refreshIdentity()
        } catch {
            await refreshIdentity()
            throw error
        }
    }

    /// Drops any `--local` `user.*` overrides so the repo falls back to the
    /// global identity. Caller refreshes — typically used from the sidebar
    /// menu's "Use global identity" entry.
    func clearLocalIdentity() async {
        await cli.clearLocalIdentity()
        await refreshIdentity()
    }
}
