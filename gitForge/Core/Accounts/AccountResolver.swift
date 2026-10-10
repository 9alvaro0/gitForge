import Foundation

nonisolated enum AccountResolution: Equatable, Sendable {
    case account(HostingAccount)
    /// Several could apply; the UI asks once and stores the choice.
    case ambiguous([HostingAccount])
    /// No instance for the host, or no accounts on it.
    case none
}

/// Which account a repo remote uses (spec §4.3), in order: the manual
/// choice, the only account, the active profile's account, the owner's
/// login; otherwise ambiguous.
nonisolated enum AccountResolver {
    static func resolve(remoteHost: String,
                        remoteOwner: String?,
                        repoPath: String,
                        remoteName: String,
                        activeProfileId: UUID?,
                        instances: [HostingInstance],
                        accounts: [HostingAccount],
                        assignments: [String: [String: UUID]]) -> AccountResolution {
        guard let host = HostingInstance.normalizedHost(remoteHost),
              let instance = instances.first(where: { $0.host == host }) else { return .none }
        let candidates = accounts.filter { $0.instanceId == instance.id }
        guard !candidates.isEmpty else { return .none }

        if let chosen = assignments[repoPath]?[remoteName],
           let account = candidates.first(where: { $0.id == chosen }) {
            return .account(account)
        }
        if candidates.count == 1 { return .account(candidates[0]) }
        if let activeProfileId,
           let account = candidates.first(where: { $0.linkedProfileId == activeProfileId }) {
            return .account(account)
        }
        if let owner = remoteOwner?.split(separator: "/").first.map({ $0.lowercased() }),
           let account = candidates.first(where: { $0.login?.lowercased() == owner }) {
            return .account(account)
        }
        return .ambiguous(candidates)
    }
}

extension AccountStore {
    func resolveAccount(remoteHost: String, remoteOwner: String?, repoPath: String,
                        remoteName: String, activeProfileId: UUID?) -> AccountResolution {
        AccountResolver.resolve(remoteHost: remoteHost, remoteOwner: remoteOwner, repoPath: repoPath,
                                remoteName: remoteName, activeProfileId: activeProfileId,
                                instances: instances, accounts: accounts, assignments: assignments)
    }
}
