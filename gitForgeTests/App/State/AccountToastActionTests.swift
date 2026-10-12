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

    @Test("Two copied accounts without a login: the one that needs attention is reconnected")
    func twoCopies() {
        let good = HostingAccount(instanceId: HostingInstance.gitLabDotCom.id, method: .personalToken, status: .ok)
        let failing = HostingAccount(instanceId: HostingInstance.gitLabDotCom.id, method: .personalToken,
                                     status: .needsAttention(.revoked))
        let action = AccountToastAction.action(for: .accountRejected(account: "gitlab.com", host: "gitlab.com"),
                                               instances: HostingInstance.builtIns, accounts: [good, failing])
        #expect(action?.route == .reconnectAccount(instanceId: HostingInstance.gitLabDotCom.id, accountId: failing.id))
    }

    @Test("No account to pin it on: opens Accounts instead of connecting a duplicate")
    func noMatch() {
        let first = HostingAccount(instanceId: HostingInstance.gitHubDotCom.id, login: "a", method: .oauth, status: .ok)
        let second = HostingAccount(instanceId: HostingInstance.gitHubDotCom.id, login: "b", method: .oauth, status: .ok)
        for accounts in [[], [first, second]] {
            let action = AccountToastAction.action(for: .accountRejected(account: "gone", host: "github.com"),
                                                   instances: HostingInstance.builtIns, accounts: accounts)
            #expect(action?.route == .openAccounts)
        }
    }
}
