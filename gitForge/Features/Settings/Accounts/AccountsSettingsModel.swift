import Foundation

/// One account row of Settings › Accounts (P4 spec §5.1).
nonisolated struct AccountRowModel: Identifiable, Equatable, Sendable {
    enum Tone: Equatable, Sendable { case ok, warn, bad }
    enum PrimaryAction: Equatable, Sendable { case reconnect, test }

    let id: UUID
    let title: String
    let subtitle: String
    let initials: String
    let avatarURL: URL?
    let statusText: String
    let tone: Tone
    let primaryAction: PrimaryAction?
    let linkedProfileId: UUID?
}

/// One instance block of Settings › Accounts.
nonisolated struct InstanceBlockModel: Identifiable, Equatable, Sendable {
    let id: UUID
    let providerLabel: String
    let host: String
    /// "OAuth", "token only", "self-hosted · token only"…
    let tag: String
    let isBuiltIn: Bool
    /// Its certificate is pinned in `RemoteHostTrust`.
    let isTrusted: Bool
    let accounts: [AccountRowModel]
}

/// What Settings › Accounts shows, derived from the store (pure).
nonisolated enum AccountsSettingsModel {
    /// Built-ins first (as stored), then self-hosted ones by host.
    static func blocks(instances: [HostingInstance], accounts: [HostingAccount],
                       copiedAccountIds: Set<UUID>, trustedHosts: Set<String> = [],
                       now: Date) -> [InstanceBlockModel] {
        let ordered = instances.filter(\.isBuiltIn) + instances.filter { !$0.isBuiltIn }.sorted { $0.host < $1.host }
        return ordered.map { instance in
            let rows = accounts
                .filter { $0.instanceId == instance.id }
                .sorted { ($0.login ?? "") < ($1.login ?? "") }
                .map { row($0, kind: instance.kind, copied: copiedAccountIds.contains($0.id), now: now) }
            let method = (instance.oauthClientId ?? "").isEmpty ? String(localized: "token only") : "OAuth"
            return InstanceBlockModel(id: instance.id, providerLabel: instance.kind.label, host: instance.host,
                                      tag: instance.isBuiltIn ? method : String(localized: "self-hosted · \(method)"),
                                      isBuiltIn: instance.isBuiltIn, isTrusted: trustedHosts.contains(instance.host),
                                      accounts: rows)
        }
    }

    /// Hosts with a trusted certificate that no instance block shows (left
    /// from the old Remote hosts section, or an instance's API host), so
    /// they can still be revoked.
    static func otherTrustedHosts(_ trustedHosts: Set<String>, instances: [HostingInstance]) -> [String] {
        let shown = Set(instances.map(\.host))
        return trustedHosts.subtracting(shown).sorted()
    }

    static func row(_ account: HostingAccount, kind: HostingInstance.Kind, copied: Bool, now: Date) -> AccountRowModel {
        let (text, tone) = status(account, kind: kind, now: now)
        return AccountRowModel(id: account.id, title: account.login ?? String(localized: "Copied token"),
                               subtitle: subtitle(account, copied: copied),
                               initials: initials(account),
                               avatarURL: account.avatarURL, statusText: text, tone: tone,
                               primaryAction: primaryAction(account.status),
                               linkedProfileId: account.linkedProfileId)
    }

    static func status(_ account: HostingAccount, kind: HostingInstance.Kind,
                       now: Date) -> (String, AccountRowModel.Tone) {
        switch account.status {
        case .ok:
            return (String(localized: "account.status.ok", defaultValue: "OK"), .ok)
        case .expiringSoon:
            guard let expiresAt = account.expiresAt else { return (String(localized: "Expires soon"), .warn) }
            let days = max(1, Int((expiresAt.timeIntervalSince(now) / 86_400).rounded(.up)))
            return (days == 1 ? String(localized: "Expires in 1 day") : String(localized: "Expires in \(days) days"), .warn)
        case .unverified:
            return (String(localized: "Unverified"), .warn)
        case .needsAttention(.revoked):
            return (String(localized: "Rejected"), .bad)
        case .needsAttention(.expired):
            return (String(localized: "Expired"), .bad)
        case .needsAttention(.missingScopes):
            let missing = HostingScopes.missing(account.scopes, kind: kind)
            let list = missing.joined(separator: ", ")
            return (missing.isEmpty || account.scopes.isEmpty ? String(localized: "Missing scopes")
                    : String(localized: "Missing scopes: \(list)"), .bad)
        case .needsAttention(.unreachable):
            return (String(localized: "Unreachable"), .warn)
        }
    }

    private static func primaryAction(_ status: HostingAccount.Status) -> AccountRowModel.PrimaryAction? {
        switch status {
        case .needsAttention: .reconnect
        case .unverified: .test
        case .ok, .expiringSoon: nil
        }
    }

    private static func subtitle(_ account: HostingAccount, copied: Bool) -> String {
        var parts: [String] = []
        if let name = account.displayName, account.login != nil, name != account.login { parts.append(name) }
        parts.append(account.method == .oauth ? "OAuth" : String(localized: "Personal token"))
        if !account.scopes.isEmpty {
            parts.append(account.scopes.joined(separator: ", "))
        } else if account.status == .ok || account.status == .expiringSoon {
            parts.append(String(localized: "scopes not verifiable"))
        }
        if copied, account.login == nil { parts.append(String(localized: "copied from an old token")) }
        if let expiresAt = account.expiresAt {
            let date = expiresAt.formatted(date: .abbreviated, time: .omitted)
            parts.append(String(localized: "expires \(date)"))
        }
        return parts.joined(separator: " · ")
    }

    static func initials(_ account: HostingAccount) -> String {
        if let name = account.displayName, !name.isEmpty {
            let letters = name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
            if !letters.isEmpty { return letters.uppercased() }
        }
        guard let login = account.login, !login.isEmpty else { return "?" }
        return String(login.prefix(2)).uppercased()
    }
}
