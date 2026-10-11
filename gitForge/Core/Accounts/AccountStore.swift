import Foundation
import Observation
import os

nonisolated enum AccountStoreError: LocalizedError, Equatable {
    case duplicateHost(String)
    case unknownInstance

    var errorDescription: String? {
        switch self {
        case .duplicateHost(let host): "\(host) is already in the list."
        case .unknownInstance: "That instance no longer exists."
        }
    }
}

/// Hosting instances, accounts and which account each repo remote uses.
/// Metadata in `accounts.json` (Application Support); secrets in an
/// `AccountSecretStore` (the Keychain in the app).
@Observable
@MainActor
final class AccountStore {
    private static let logger = Logger(subsystem: "com.warwarelabs.gitForge", category: "accounts")
    /// Written to the file. Stays 1 so builds from before phase 4 can still
    /// read it (they ignore `systemChoices`) instead of quarantining it.
    private static let schemaVersion = 1
    /// Newest version this build reads: 2 is a file written by an earlier
    /// phase-4 build.
    private static let newestReadableVersion = 2

    private(set) var instances: [HostingInstance] = HostingInstance.builtIns
    private(set) var accounts: [HostingAccount] = []
    /// repo path → remote name → account id.
    private(set) var assignments: [String: [String: RepoAccountChoice]] = [:]
    /// Old store host → the account its token was copied into.
    var legacyHostAccounts: [String: UUID] = [:]
    /// Set once a sync read and copied every old host token without error.
    var migratedLegacyTokens = false {
        didSet { if oldValue != migratedLegacyTokens { save() } }
    }
    /// Hosts whose old token no longer feeds an account: the user reconnected
    /// it in gitForge, so the sync must not overwrite or re-create it.
    private(set) var detachedLegacyHosts: Set<String> = []

    private let fileURL: URL
    /// Also used by the token refresher, off the main actor.
    let secrets: AccountSecretStore
    /// github.com and gitlab.com with this build's OAuth client ids. Never
    /// persisted, so a new build's ids always win.
    private let builtIns: [HostingInstance]

    private struct Stored: Codable {
        let version: Int
        let instances: [HostingInstance]
        let accounts: [HostingAccount]
        /// Account choices only, as builds before phase 4 expect them.
        let assignments: [String: [String: UUID]]
        let migratedLegacyTokens: Bool
        /// Optional: absent in files written before the sync existed.
        let legacyHostAccounts: [String: UUID]?
        /// Optional: absent in files written before phase 2.
        let detachedLegacyHosts: [String]?
        /// Optional (phase 4): repo path → remotes using the system's
        /// credentials. Older builds ignore it.
        let systemChoices: [String: [String]]?
    }

    private struct VersionProbe: Decodable { let version: Int }

    /// What an earlier phase-4 build wrote as version 2: all choices in
    /// `assignments`.
    private struct StoredDraftV2: Decodable {
        let instances: [HostingInstance]
        let accounts: [HostingAccount]
        let assignments: [String: [String: RepoAccountChoice]]
        let migratedLegacyTokens: Bool
        let legacyHostAccounts: [String: UUID]?
        let detachedLegacyHosts: [String]?
    }

    init(directory: URL? = nil, secrets: AccountSecretStore = KeychainAccountSecretStore(),
         clientIds: OAuthClientIDs = .bundled) {
        let dir = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!.appendingPathComponent("gitForge", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("accounts.json")
        self.secrets = secrets
        self.builtIns = HostingInstance.builtIns(clientIds: clientIds)
        self.instances = builtIns
        load()
    }

    // MARK: Instances

    func instance(forHost host: String) -> HostingInstance? {
        guard let normalized = HostingInstance.normalizedHost(host) else { return nil }
        return instances.first { $0.host == normalized }
    }

    func addInstance(_ instance: HostingInstance) throws(AccountStoreError) {
        guard self.instance(forHost: instance.host) == nil else { throw .duplicateHost(instance.host) }
        instances.append(instance)
        save()
    }

    /// Built-ins stay. Removing an instance removes its accounts too.
    func removeInstance(_ id: UUID) {
        guard let instance = instances.first(where: { $0.id == id }), !instance.isBuiltIn else { return }
        for account in accounts where account.instanceId == id {
            removeAccount(account.id)
        }
        instances.removeAll { $0.id == id }
        save()
    }

    /// "OAuth client ID…" of a self-hosted instance; blank clears it.
    /// Built-ins keep the ids this build ships.
    func setOAuthClientId(_ clientId: String?, forInstance instanceId: UUID) {
        guard let index = instances.firstIndex(where: { $0.id == instanceId }), !instances[index].isBuiltIn else { return }
        let trimmed = clientId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        instances[index].oauthClientId = trimmed.isEmpty ? nil : trimmed
        save()
    }

    // MARK: Accounts

    func accounts(in instanceId: UUID) -> [HostingAccount] {
        accounts.filter { $0.instanceId == instanceId }
    }

    /// Writes the secret first: if the Keychain refuses, no account is added.
    func addAccount(_ account: HostingAccount, secret: AccountSecret) throws {
        guard instances.contains(where: { $0.id == account.instanceId }) else { throw AccountStoreError.unknownInstance }
        try secrets.write(secret, for: account.id)
        accounts.append(account)
        save()
    }

    func updateAccount(_ account: HostingAccount) {
        guard let index = accounts.firstIndex(where: { $0.id == account.id }) else { return }
        accounts[index] = account
        save()
    }

    func removeAccount(_ id: UUID) {
        secrets.delete(id)
        accounts.removeAll { $0.id == id }
        // The old token mustn't bring a removed account back on next launch.
        detachedLegacyHosts.formUnion(legacyHostAccounts.filter { $0.value == id }.map(\.key))
        legacyHostAccounts = legacyHostAccounts.filter { $0.value != id }
        for (repo, remotes) in assignments {
            let kept = remotes.filter { $0.value != .account(id) }
            assignments[repo] = kept.isEmpty ? nil : kept
        }
        save()
    }

    func secret(for accountId: UUID) -> AccountSecret? {
        secrets.read(accountId)
    }

    /// Stops the old-token sync for the hosts that fed `accountId`.
    func detachFromLegacy(_ accountId: UUID) {
        let hosts = legacyHostAccounts.filter { $0.value == accountId }.map(\.key)
        guard !hosts.isEmpty else { return }
        detachedLegacyHosts.formUnion(hosts)
        for host in hosts { legacyHostAccounts[host] = nil }
        save()
    }

    // MARK: Repo assignments

    func choice(repoPath: String, remoteName: String) -> RepoAccountChoice? {
        assignments[repoPath]?[remoteName]
    }

    func assignedAccountId(repoPath: String, remoteName: String) -> UUID? {
        choice(repoPath: repoPath, remoteName: remoteName)?.accountId
    }

    /// `nil` clears the choice (back to automatic).
    func setChoice(_ choice: RepoAccountChoice?, repoPath: String, remoteName: String) {
        var remotes = assignments[repoPath] ?? [:]
        remotes[remoteName] = choice
        assignments[repoPath] = remotes.isEmpty ? nil : remotes
        save()
    }

    /// Shorthand for an account choice; `nil` clears it.
    func assign(_ accountId: UUID?, repoPath: String, remoteName: String) {
        setChoice(accountId.map(RepoAccountChoice.account), repoPath: repoPath, remoteName: remoteName)
    }

    // MARK: Persistence

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            let version = try JSONDecoder().decode(VersionProbe.self, from: data).version
            guard version <= Self.newestReadableVersion else {
                Self.logger.error("accounts.json version \(version, privacy: .public) is newer than supported")
                quarantine()
                return
            }
            let stored: Stored
            let choices: [String: [String: RepoAccountChoice]]
            if version == 2 {
                let draft = try JSONDecoder().decode(StoredDraftV2.self, from: data)
                stored = Stored(version: Self.schemaVersion, instances: draft.instances, accounts: draft.accounts,
                                assignments: [:], migratedLegacyTokens: draft.migratedLegacyTokens,
                                legacyHostAccounts: draft.legacyHostAccounts,
                                detachedLegacyHosts: draft.detachedLegacyHosts, systemChoices: nil)
                choices = draft.assignments
            } else {
                stored = try JSONDecoder().decode(Stored.self, from: data)
                var merged = stored.assignments.mapValues { $0.mapValues(RepoAccountChoice.account) }
                for (repo, remotes) in stored.systemChoices ?? [:] {
                    for remote in remotes { merged[repo, default: [:]][remote] = .system }
                }
                choices = merged
            }
            // Built-ins always come first and win over any stored copy.
            let builtInIds = Set(builtIns.map(\.id))
            instances = builtIns + stored.instances.filter { !builtInIds.contains($0.id) }
            accounts = stored.accounts.filter { account in instances.contains { $0.id == account.instanceId } }
            assignments = choices
            migratedLegacyTokens = stored.migratedLegacyTokens
            legacyHostAccounts = (stored.legacyHostAccounts ?? [:]).filter { mapping in
                accounts.contains { $0.id == mapping.value }
            }
            detachedLegacyHosts = Set(stored.detachedLegacyHosts ?? [])
        } catch {
            Self.logger.error("Failed to load accounts.json: \(error.localizedDescription, privacy: .public)")
            quarantine()
        }
    }

    private func save() {
        var accountChoices: [String: [String: UUID]] = [:]
        var systemChoices: [String: [String]] = [:]
        for (repo, remotes) in assignments {
            for (remote, choice) in remotes {
                switch choice {
                case .account(let id): accountChoices[repo, default: [:]][remote] = id
                case .system: systemChoices[repo, default: []].append(remote)
                }
            }
        }
        let stored = Stored(version: Self.schemaVersion,
                            instances: instances.filter { !$0.isBuiltIn },
                            accounts: accounts,
                            assignments: accountChoices,
                            migratedLegacyTokens: migratedLegacyTokens,
                            legacyHostAccounts: legacyHostAccounts,
                            detachedLegacyHosts: detachedLegacyHosts.sorted(),
                            systemChoices: systemChoices.isEmpty ? nil : systemChoices.mapValues { $0.sorted() })
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(stored).write(to: fileURL, options: .atomic)
        } catch {
            Self.logger.error("Failed to save accounts.json: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Keeps an unreadable file as evidence instead of overwriting it.
    private func quarantine() {
        let stamp = ISO8601DateFormatter().string(from: .now).replacingOccurrences(of: ":", with: "-")
        let dest = fileURL.deletingPathExtension().appendingPathExtension("corrupted.\(stamp).json")
        try? FileManager.default.moveItem(at: fileURL, to: dest)
    }
}

/// The pre-accounts token store, one token per host. Reads throw when the
/// store can't be read (e.g. Keychain access denied), so that isn't taken
/// for "no token".
nonisolated protocol LegacyTokenSource: Sendable {
    func legacyHosts() throws -> [String]
    /// `nil` = no token stored for `host`.
    func legacyToken(for host: String) throws -> String?
}

extension AccountStore {
    /// Syncs each old per-host token into a token account (spec §4.4). Runs
    /// every launch until phase 5 retires the old store, so a token added
    /// or rotated in Settings › Remote hosts meanwhile still reaches the
    /// accounts. Non-destructive: the old entries stay until phase 5.
    /// `migratedLegacyTokens` is set only once a run read and copied every
    /// host without error; phase 5 must see it set before deleting.
    func migrateLegacyTokens(from legacy: LegacyTokenSource) {
        guard let hosts = try? legacy.legacyHosts() else { return }
        var complete = true
        for host in hosts {
            guard let normalized = HostingInstance.normalizedHost(host),
                  let kind = Self.legacyKind(forHost: normalized) else { continue }
            if detachedLegacyHosts.contains(normalized) { continue }
            let token: String
            do {
                guard let stored = try legacy.legacyToken(for: host) else { continue }
                token = stored
            } catch {
                complete = false
                continue
            }
            let target: HostingInstance
            if let existing = instance(forHost: normalized) {
                target = existing
            } else {
                target = HostingInstance(kind: kind, host: normalized)
                do { try addInstance(target) } catch { continue }
            }
            // Already synced: keep its secret current (only while it's still
            // a token account; a reconnect via OAuth owns its own secret). A
            // changed token is checked again by the validator.
            if let mapped = legacyHostAccounts[normalized],
               let account = accounts.first(where: { $0.id == mapped }) {
                if account.method == .personalToken, secret(for: mapped)?.accessToken != token {
                    do {
                        try secrets.write(AccountSecret(accessToken: token), for: mapped)
                        var rotated = account
                        rotated.status = .unverified
                        rotated.lastValidatedAt = nil
                        updateAccount(rotated)
                    } catch {
                        complete = false
                    }
                }
                continue
            }
            // Copied by an earlier version, before the host map existed.
            if let earlier = accounts(in: target.id).first(where: {
                $0.method == .personalToken && !legacyHostAccounts.values.contains($0.id)
                    && secret(for: $0.id)?.accessToken == token
            }) {
                legacyHostAccounts[normalized] = earlier.id
                save()
                continue
            }
            let account = HostingAccount(instanceId: target.id, method: .personalToken, status: .unverified)
            do {
                try addAccount(account, secret: AccountSecret(accessToken: token))
                legacyHostAccounts[normalized] = account.id
                save()
            } catch {
                complete = false
            }
        }
        if complete { migratedLegacyTokens = true }
    }

    /// The old host-name heuristic, used only to type migrated hosts.
    static func legacyKind(forHost host: String) -> HostingInstance.Kind? {
        if host == "github.com" || host.hasSuffix(".github.com") { return .github }
        if host.contains("gitlab") { return .gitlab }
        return nil
    }
}
