import Foundation
import Testing
@testable import gitForge

@Suite("AccountToastAction")
struct AccountToastActionTests {
    static let account = HostingAccount(instanceId: HostingInstance.gitHubDotCom.id, login: "octo", method: .oauth)

    @Test("A rejected account offers Reconnect on that account")
    func rejected() {
        let action = AccountToastAction.action(for: .accountRejected(account: "octo", host: "github.com"),
                                               instances: HostingInstance.builtIns, accounts: [Self.account])
        #expect(action == ToastAction(title: "Reconnect account",
                                      route: .reconnectAccount(instanceId: HostingInstance.gitHubDotCom.id, accountId: Self.account.id)))
    }

    @Test("A copied account without a login is matched by host")
    func copied() {
        let copied = HostingAccount(instanceId: HostingInstance.gitLabDotCom.id, method: .personalToken)
        let action = AccountToastAction.action(for: .accountRejected(account: "gitlab.com", host: "gitlab.com"),
                                               instances: HostingInstance.builtIns, accounts: [copied])
        #expect(action?.route == .reconnectAccount(instanceId: HostingInstance.gitLabDotCom.id, accountId: copied.id))
    }

    @Test("A missing scope opens Accounts; other failures offer nothing")
    func others() {
        #expect(AccountToastAction.action(for: .missingScope("workflow"), instances: [], accounts: [])?.route == .openAccounts)
        #expect(AccountToastAction.action(for: .network, instances: [], accounts: []) == nil)
    }
}
