import Foundation

/// The toast button for an account failure (P4 spec §5.6).
nonisolated enum AccountToastAction {
    static func action(for failure: RemoteFailure, instances: [HostingInstance],
                       accounts: [HostingAccount]) -> ToastAction? {
        switch failure {
        case .accountRejected(let account, let host):
            guard let instance = instances.first(where: { $0.host == host }) else {
                return ToastAction(title: "Open accounts", route: .openAccounts)
            }
            let match = accounts.first { $0.instanceId == instance.id && ($0.login ?? host) == account }
            return ToastAction(title: "Reconnect account",
                               route: .reconnectAccount(instanceId: instance.id, accountId: match?.id))
        case .missingScope:
            return ToastAction(title: "Open accounts", route: .openAccounts)
        default:
            return nil
        }
    }
}
