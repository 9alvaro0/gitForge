import Foundation

/// One "Hosting account · <remote>" section of the profile menu (P4 spec §5.4).
nonisolated struct RepoAccountSection: Identifiable, Equatable, Sendable {
    enum Entry: Identifiable, Equatable, Sendable {
        case automatic(label: String, checked: Bool)
        case account(id: UUID, label: String, checked: Bool)
        case system(checked: Bool)
        case connect(instanceId: UUID)

        var id: String {
            switch self {
            case .automatic: "automatic"
            case .account(let id, _, _): id.uuidString
            case .system: "system"
            case .connect: "connect"
            }
        }
    }

    let remote: String
    let instanceId: UUID
    let title: String
    let current: String
    let entries: [Entry]
    var id: String { remote }
}

/// The profile menu's account sections for a repo (pure).
nonisolated enum RepoAccountMenuModel {
    static func sections(remotes: [GitRemoteURL], repoPath: String, activeProfileId: UUID?,
                         instances: [HostingInstance], accounts: [HostingAccount],
                         assignments: [String: [String: RepoAccountChoice]]) -> [RepoAccountSection] {
        remotes.compactMap { remote in
            guard GitCredentialInjection.context(forRemoteURL: remote.url) != nil,
                  let host = GitCredentialInjection.host(forRemoteURL: remote.url),
                  let instance = instances.first(where: { $0.host == host }) else { return nil }
            let usable = accounts
                .filter { $0.instanceId == instance.id && AccountGitCredentials.signs($0) }
                .sorted { ($0.login ?? "") < ($1.login ?? "") }
            let choice = assignments[repoPath]?[remote.name]
            var withoutChoice = assignments
            withoutChoice[repoPath]?[remote.name] = nil
            let automatic = AccountResolver.resolve(remoteHost: host, remoteOwner: GitCredentialInjection.owner(forRemoteURL: remote.url),
                                                    repoPath: repoPath, remoteName: remote.name,
                                                    activeProfileId: activeProfileId, instances: instances,
                                                    accounts: usable, assignments: withoutChoice)
            let automaticLabel: String = switch automatic {
            case .account(let account): String(localized: "Automatic (\(name(account)))")
            case .ambiguous: String(localized: "Automatic (ask)")
            case .none: String(localized: "Automatic (system credentials)")
            }
            let chosenAccount = choice?.accountId.flatMap { id in usable.first { $0.id == id } }
            let current: String
            if choice == .system {
                current = String(localized: "System credentials")
            } else if let chosenAccount {
                current = "\(name(chosenAccount)) @ \(host)"
            } else {
                switch automatic {
                case .account(let account): current = "\(name(account)) @ \(host)"
                case .ambiguous: current = String(localized: "Choose…")
                case .none: current = String(localized: "System credentials")
                }
            }
            var entries: [RepoAccountSection.Entry] = [.automatic(label: automaticLabel, checked: choice == nil)]
            entries += usable.map { .account(id: $0.id, label: name($0), checked: choice == .account($0.id)) }
            entries += [.system(checked: choice == .system), .connect(instanceId: instance.id)]
            let remoteName = remote.name
            return RepoAccountSection(remote: remote.name, instanceId: instance.id,
                                      title: String(localized: "Hosting account · \(remoteName)"), current: current, entries: entries)
        }
    }

    private static func name(_ account: HostingAccount) -> String {
        account.login ?? String(localized: "Copied token")
    }
}
