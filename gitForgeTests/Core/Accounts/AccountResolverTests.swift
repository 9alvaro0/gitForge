import Foundation
import Testing
@testable import gitForge

@Suite("AccountResolver")
struct AccountResolverTests {

    private static let gh = HostingInstance.gitHubDotCom
    private static let personal = UUID()
    private static let work = UUID()

    private static func account(_ login: String?, profile: UUID? = nil) -> HostingAccount {
        HostingAccount(instanceId: gh.id, login: login, method: .oauth, status: .ok, linkedProfileId: profile)
    }

    private static func resolve(_ accounts: [HostingAccount], owner: String? = "someone", profile: UUID? = nil,
                                assignments: [String: [String: RepoAccountChoice]] = [:], host: String = "github.com") -> AccountResolution {
        AccountResolver.resolve(remoteHost: host, remoteOwner: owner, repoPath: "/r/app", remoteName: "origin",
                                activeProfileId: profile, instances: HostingInstance.builtIns,
                                accounts: accounts, assignments: assignments)
    }

    @Test("1 · a manual choice for the repo remote wins")
    func manual() {
        let a = Self.account("alvaro"), b = Self.account("alvaro-work")
        #expect(Self.resolve([a, b], assignments: ["/r/app": ["origin": .account(b.id)]]) == .account(b))
    }

    @Test("2 · the only account on the instance")
    func single() {
        let a = Self.account("alvaro")
        #expect(Self.resolve([a]) == .account(a))
    }

    @Test("3 · the account linked to the repo's active identity profile")
    func profile() {
        let a = Self.account("alvaro", profile: Self.personal), b = Self.account("alvaro-work", profile: Self.work)
        #expect(Self.resolve([a, b], profile: Self.work) == .account(b))
    }

    @Test("4 · the account whose login is the remote owner, ignoring case and GitLab subgroups")
    func owner() {
        let a = Self.account("Alvaro"), b = Self.account("acme")
        #expect(Self.resolve([a, b], owner: "alvaro") == .account(a))
        #expect(Self.resolve([a, b], owner: "ACME/platform/ios") == .account(b))
    }

    @Test("5 · otherwise ambiguous with the candidates; no instance or no accounts → none")
    func ambiguousAndNone() {
        let a = Self.account("alvaro"), b = Self.account("other")
        #expect(Self.resolve([a, b]) == .ambiguous([a, b]))
        #expect(Self.resolve([]) == .none)
        #expect(Self.resolve([a], host: "bitbucket.org") == .none)
    }

    @Test("A stale manual choice (account removed) falls through to the next rules")
    func staleChoice() {
        let a = Self.account("alvaro")
        #expect(Self.resolve([a], assignments: ["/r/app": ["origin": .account(UUID())]]) == .account(a))
    }
}
