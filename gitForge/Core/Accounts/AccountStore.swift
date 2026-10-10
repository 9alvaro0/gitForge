import Foundation
import Observation
import os

enum AccountStoreError: LocalizedError, Equatable {
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
    private static let schemaVersion = 1

    private(set) var instances: [HostingInstance] = HostingInstance.builtIns
    private(set) var accounts: [HostingAccount] = []
    /// repo path → remote name → account id.
    private(set) var assignments: [String: [String: UUID]] = [:]
    /// Set once the pre-accounts host tokens have been copied over.
    var migratedLegacyTokens = false {
        didSet { if oldValue != migratedLegacyTokens { save() } }
    }

    private let fileURL: URL
    private let secrets: AccountSecretStore

    private struct Stored: Codable {
        let version: Int
        let instances: [HostingInstance]
        let accounts: [HostingAccount]
        let assignments: [String: [String: UUID]]
        let migratedLegacyTokens: Bool
    }

    init(directory: URL? = nil, secrets: AccountSecretStore = KeychainAccountSecretStore()) {
        let dir = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!.appendingPathComponent("gitForge", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("accounts.json")
        self.secrets = secrets
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
        for (repo, remotes) in assignments {
            let kept = remotes.filter { $0.value != id }
            assignments[repo] = kept.isEmpty ? nil : kept
        }
        save()
    }

    func secret(for accountId: UUID) -> AccountSecret? {
        secrets.read(accountId)
    }

    // MARK: Repo assignments

    func assignedAccountId(repoPath: String, remoteName: String) -> UUID? {
        assignments[repoPath]?[remoteName]
    }

    /// `nil` clears the choice.
    func assign(_ accountId: UUID?, repoPath: String, remoteName: String) {
        var remotes = assignments[repoPath] ?? [:]
        remotes[remoteName] = accountId
        assignments[repoPath] = remotes.isEmpty ? nil : remotes
        save()
    }

    // MARK: Persistence

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let stored = try JSONDecoder().decode(Stored.self, from: Data(contentsOf: fileURL))
            guard stored.version <= Self.schemaVersion else {
                Self.logger.error("accounts.json version \(stored.version, privacy: .public) is newer than supported")
                quarantine()
                return
            }
            // Built-ins always come first and win over any stored copy.
            let builtInIds = Set(HostingInstance.builtIns.map(\.id))
            instances = HostingInstance.builtIns + stored.instances.filter { !builtInIds.contains($0.id) }
            accounts = stored.accounts.filter { account in instances.contains { $0.id == account.instanceId } }
            assignments = stored.assignments
            migratedLegacyTokens = stored.migratedLegacyTokens
        } catch {
            Self.logger.error("Failed to load accounts.json: \(error.localizedDescription, privacy: .public)")
            quarantine()
        }
    }

    private func save() {
        let stored = Stored(version: Self.schemaVersion,
                            instances: instances.filter { !$0.isBuiltIn },
                            accounts: accounts,
                            assignments: assignments,
                            migratedLegacyTokens: migratedLegacyTokens)
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

/// The pre-accounts token store, one token per host.
protocol LegacyTokenSource {
    func knownHosts() -> [String]
    func token(for host: String) -> String?
}

extension AccountStore {
    /// Copies each old per-host token into a token account (spec §4.4).
    /// Non-destructive in phase 1: the old entries stay until phase 5 moves
    /// PRs and clone onto accounts. Marked done only when every copy landed,
    /// so a Keychain failure is retried next launch.
    func migrateLegacyTokens(from legacy: LegacyTokenSource) {
        guard !migratedLegacyTokens else { return }
        var allCopied = true
        for host in legacy.knownHosts() {
            guard let token = legacy.token(for: host),
                  let normalized = HostingInstance.normalizedHost(host),
                  let kind = Self.legacyKind(forHost: normalized) else { continue }
            let target: HostingInstance
            if let existing = instance(forHost: normalized) {
                target = existing
            } else {
                target = HostingInstance(kind: kind, host: normalized)
                do { try addInstance(target) } catch { continue }
            }
            // Already copied on an earlier, partly failed run.
            if accounts(in: target.id).contains(where: { $0.method == .personalToken && secret(for: $0.id)?.accessToken == token }) {
                continue
            }
            do {
                try addAccount(HostingAccount(instanceId: target.id, method: .personalToken, status: .unverified),
                               secret: AccountSecret(accessToken: token))
            } catch {
                allCopied = false
            }
        }
        if allCopied { migratedLegacyTokens = true }
    }

    /// The old host-name heuristic, used only to type migrated hosts.
    static func legacyKind(forHost host: String) -> HostingInstance.Kind? {
        if host == "github.com" || host.hasSuffix(".github.com") { return .github }
        if host.contains("gitlab") { return .gitlab }
        return nil
    }
}
