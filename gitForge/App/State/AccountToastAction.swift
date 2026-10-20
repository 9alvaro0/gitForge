import Foundation

/// The toast button for an account failure (P4 spec §5.6).
nonisolated enum AccountToastAction {
    static func action(for failure: RemoteFailure, instances: [HostingInstance],
                       accounts: [HostingAccount]) -> ToastAction? {
        switch failure {
        case .accountRejected(let account, let host):
            guard let instance = instances.first(where: { $0.host == host }) else {
                return ToastAction(title: String(localized: "Open accounts"), route: .openAccounts)
            }
            guard let match = rejectedAccount(named: account, on: instance, among: accounts) else {
                // Reconnecting nobody in particular would add a duplicate.
                return ToastAction(title: String(localized: "Open accounts"), route: .openAccounts)
            }
            return ToastAction(title: String(localized: "Reconnect account"),
                               route: .reconnectAccount(instanceId: instance.id, accountId: match.id))
        case .missingScope:
            return ToastAction(title: String(localized: "Open accounts"), route: .openAccounts)
        default:
            return nil
        }
    }

    /// The account the error names: its login (or the host, for a copied
    /// token without one). When that isn't a single account, the only one
    /// on the instance that needs attention — git marks it before failing.
    private static func rejectedAccount(named name: String, on instance: HostingInstance,
                                        among accounts: [HostingAccount]) -> HostingAccount? {
        let onInstance = accounts.filter { $0.instanceId == instance.id }
        let named = onInstance.filter { ($0.login ?? instance.host) == name }
        if named.count == 1 { return named[0] }
        let failing = (named.isEmpty ? onInstance : named).filter { !AccountGitCredentials.signs($0) }
        return failing.count == 1 ? failing[0] : nil
    }
}
