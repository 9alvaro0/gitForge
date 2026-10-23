import Foundation
import Testing
@testable import gitForge

@Suite("Followed repos")
struct FollowedReposTests {
    static let gitlab = HostingInstance.gitLabDotCom
    static let marta = HostingAccount(instanceId: gitlab.id, login: "marta", method: .oauth, status: .ok)
    static let octo = HostingAccount(instanceId: gitlab.id, login: "octo", method: .oauth, status: .ok)
    static let ana = HostingAccount(instanceId: gitlab.id, login: "ana", method: .oauth, status: .ok)

    static func host(_ path: String) -> RemoteHost { RemoteHost.make(fullName: path, on: gitlab)! }
    static func local(_ path: String, opened: TimeInterval, assigned: UUID? = nil) -> LocalRemote {
        LocalRemote(host: host(path), repository: Repository(url: URL(fileURLWithPath: "/r/\(path)"),
                                                            lastOpenedAt: Date(timeIntervalSince1970: opened)),
                    assignedAccountId: assigned)
    }
    static func activity(_ path: String, _ account: HostingAccount, at: TimeInterval) -> ActivityCandidate {
        ActivityCandidate(host: host(path), accountId: account.id, at: Date(timeIntervalSince1970: at),
                          cloneURL: "https://gitlab.com/\(path).git")
    }

    @Test("Local and activity for the same repo, any case, are one repo with the local's account")
    func dedupe() {
        let set = FollowedRepos.merge(local: [Self.local("Apps/Payments", opened: 10, assigned: Self.octo.id)],
                                      activity: [Self.activity("apps/payments", Self.marta, at: 50)],
                                      accounts: [Self.marta, Self.octo], instances: [Self.gitlab])
        #expect(set.repos.count == 1)
        #expect(set.repos[0].accountId == Self.octo.id)
        #expect(set.repos[0].sources == [.local, .activity])
        #expect(set.repos[0].lastActivity == Date(timeIntervalSince1970: 50))
        #expect(set.repos[0].localURL == URL(fileURLWithPath: "/r/Apps/Payments"))
    }

    @Test("Without an assignment the owner's account wins, then the first usable one")
    func accountChoice() {
        let set = FollowedRepos.merge(local: [Self.local("octo/tools", opened: 1), Self.local("team/api", opened: 2)],
                                      activity: [], accounts: [Self.marta, Self.octo], instances: [Self.gitlab])
        #expect(set.repos.first { $0.host.repo == "tools" }?.accountId == Self.octo.id)
        #expect(set.repos.first { $0.host.repo == "api" }?.accountId == Self.marta.id)
    }

    @Test("The owner's account comes first, the rest in the order given")
    func accountsInPreference() {
        #expect(FollowedRepos.accountsInPreference(for: Self.host("octo/tools"), among: [Self.marta, Self.octo, Self.ana])
                == [Self.octo, Self.marta, Self.ana])
        // No account is the owner's: the order given.
        #expect(FollowedRepos.accountsInPreference(for: Self.host("team/api"), among: [Self.marta, Self.octo, Self.ana])
                == [Self.marta, Self.octo, Self.ana])
    }

    @Test("A clone with no account of its own takes one that saw its activity, not the instance's first")
    func unassignedLocalFollowsActivity() {
        // Without the activity, marta would read it: first, and neither login is the owner.
        let set = FollowedRepos.merge(local: [Self.local("team/api", opened: 1)],
                                      activity: [Self.activity("team/api", Self.octo, at: 5)],
                                      accounts: [Self.marta, Self.octo], instances: [Self.gitlab])
        #expect(set.repos.map(\.accountId) == [Self.octo.id])
        #expect(set.repos.first?.sources == [.local, .activity])
    }

    @Test("A clone with an account of its own keeps it, whoever saw its activity")
    func assignedLocalKeepsAccount() {
        let set = FollowedRepos.merge(local: [Self.local("team/api", opened: 1, assigned: Self.marta.id)],
                                      activity: [Self.activity("team/api", Self.octo, at: 5)],
                                      accounts: [Self.marta, Self.octo], instances: [Self.gitlab])
        #expect(set.repos.map(\.accountId) == [Self.marta.id])
    }

    @Test("A local repo on an instance without a usable account is left out")
    func noAccount() {
        let github = LocalRemote(host: RemoteHost.make(fullName: "octo/app", on: .gitHubDotCom)!,
                                 repository: Repository(url: URL(fileURLWithPath: "/r/app")), assignedAccountId: nil)
        #expect(FollowedRepos.merge(local: [github], activity: [], accounts: [Self.marta],
                                    instances: [.gitHubDotCom, Self.gitlab]).repos.isEmpty)
    }

    // MARK: Membership of the clones

    /// The keys of repos an account of the instance belongs to.
    static func members(_ paths: String...) -> [UUID: Set<String>] {
        [gitlab.id: Set(paths.map { FollowedRepos.key(host($0)) })]
    }

    @Test("On an instance whose members are known, a clone that isn't among them is left out")
    func cloneOutsideTheMembers() {
        let set = FollowedRepos.merge(local: [Self.local("team/app", opened: 1), Self.local("oss/big", opened: 2)],
                                      activity: [], accounts: [Self.marta], instances: [Self.gitlab],
                                      memberKeys: Self.members("team/app", "team/api"))
        #expect(set.repos.map(\.host.repo) == ["app"])
        #expect(set.dropped == 0)
    }

    @Test("A clone among the members stays, whatever the case of its path or of the member's")
    func cloneAmongTheMembersAnyCase() {
        let set = FollowedRepos.merge(local: [Self.local("Team/App", opened: 1)], activity: [],
                                      accounts: [Self.marta], instances: [Self.gitlab],
                                      memberKeys: Self.members("TEAM/app"))
        #expect(set.repos.map(\.host.repo) == ["App"])
        #expect(set.repos.first?.sources == [.local])
    }

    @Test("Known members that are none leave every clone of the instance out")
    func knownWithNoMembers() {
        let set = FollowedRepos.merge(local: [Self.local("oss/big", opened: 1)], activity: [],
                                      accounts: [Self.marta], instances: [Self.gitlab],
                                      memberKeys: [Self.gitlab.id: []])
        #expect(set.repos.isEmpty)
    }

    @Test("On an instance with no entry in the member keys, every clone stays")
    func unknownInstanceKeepsClones() {
        let set = FollowedRepos.merge(local: [Self.local("team/app", opened: 1), Self.local("oss/big", opened: 2)],
                                      activity: [], accounts: [Self.marta], instances: [Self.gitlab],
                                      memberKeys: [:])
        #expect(set.repos.map(\.host.repo).sorted() == ["app", "big"])
    }

    @Test("Members of another instance don't filter the clones of this one")
    func otherInstanceMembersDontFilter() {
        let github = LocalRemote(host: RemoteHost.make(fullName: "oss/big", on: .gitHubDotCom)!,
                                 repository: Repository(url: URL(fileURLWithPath: "/r/big")), assignedAccountId: nil)
        let octoHub = HostingAccount(instanceId: HostingInstance.gitHubDotCom.id, login: "octo",
                                     method: .oauth, status: .ok)
        // GitLab is known and lists team/app; GitHub is unknown.
        let set = FollowedRepos.merge(local: [Self.local("oss/big", opened: 1), github], activity: [],
                                      accounts: [Self.marta, octoHub], instances: [Self.gitlab, .gitHubDotCom],
                                      memberKeys: Self.members("team/app"))
        #expect(set.repos.map(\.host.host) == ["github.com"])
    }

    @Test("A clone also seen through activity stays even if the members don't list it")
    func cloneWithActivityStays() {
        let set = FollowedRepos.merge(local: [Self.local("oss/big", opened: 1)],
                                      activity: [Self.activity("OSS/Big", Self.marta, at: 5)],
                                      accounts: [Self.marta], instances: [Self.gitlab],
                                      memberKeys: Self.members("team/app"))
        #expect(set.repos.count == 1)
        #expect(set.repos[0].sources == [.local, .activity])
        #expect(set.repos[0].host.repo == "big")
        #expect(set.repos[0].localURL == URL(fileURLWithPath: "/r/oss/big"))
    }

    @Test("Activity of an account that isn't usable on the instance doesn't keep a clone that isn't a member")
    func foreignActivityDoesNotKeepTheClone() {
        let stranger = HostingAccount(instanceId: HostingInstance.gitHubDotCom.id, login: "marta",
                                      method: .oauth, status: .ok)
        let set = FollowedRepos.merge(local: [Self.local("oss/big", opened: 1)],
                                      activity: [Self.activity("oss/big", stranger, at: 5)],
                                      accounts: [Self.marta, stranger], instances: [.gitHubDotCom, Self.gitlab],
                                      memberKeys: Self.members("team/app"))
        #expect(set.repos.isEmpty)
    }

    @Test("Activity-only repos aren't filtered by the member keys")
    func activityRepoIsNotFiltered() {
        let set = FollowedRepos.merge(local: [], activity: [Self.activity("oss/big", Self.marta, at: 5)],
                                      accounts: [Self.marta], instances: [Self.gitlab],
                                      memberKeys: [Self.gitlab.id: []])
        #expect(set.repos.map(\.host.repo) == ["big"])
    }

    @Test("Over 100 repos keeps the 100 most recent and counts the rest")
    func limit() {
        let activity = (0..<103).map { Self.activity("team/repo\($0)", Self.marta, at: TimeInterval($0)) }
        let set = FollowedRepos.merge(local: [], activity: activity, accounts: [Self.marta], instances: [Self.gitlab])
        #expect(set.repos.count == 100)
        #expect(set.dropped == 3)
        #expect(set.repos.first?.host.repo == "repo102")
        #expect(!set.repos.contains { $0.host.repo == "repo0" })
    }

    @Test("Clone URL: the API's when known, else built from the host")
    func cloneURL() {
        let set = FollowedRepos.merge(local: [Self.local("team/app", opened: 1)], activity: [],
                                      accounts: [Self.marta], instances: [Self.gitlab])
        #expect(set.repos[0].cloneURL == "https://gitlab.com/team/app.git")
    }

    @Test("A local repo that also has activity clones from the API's URL")
    func apiCloneURLWins() {
        let moved = ActivityCandidate(host: Self.host("team/app"), accountId: Self.marta.id,
                                      at: Date(timeIntervalSince1970: 5),
                                      cloneURL: "https://gitlab.com/team/app-renamed.git")
        let set = FollowedRepos.merge(local: [Self.local("team/app", opened: 1)], activity: [moved],
                                      accounts: [Self.marta], instances: [Self.gitlab])
        #expect(set.repos[0].cloneURL == "https://gitlab.com/team/app-renamed.git")
    }

    @Test("The same repo seen by two accounts is one repo, with an account that saw it")
    func twoAccounts() {
        let set = FollowedRepos.merge(
            local: [],
            activity: [Self.activity("octo/tools", Self.marta, at: 5), Self.activity("octo/tools", Self.octo, at: 9),
                       Self.activity("team/api", Self.octo, at: 3)],
            accounts: [Self.marta, Self.octo], instances: [Self.gitlab])
        #expect(set.repos.count == 2)
        #expect(set.repos.first { $0.host.repo == "tools" }?.accountId == Self.octo.id)
        #expect(set.repos.first { $0.host.repo == "api" }?.accountId == Self.octo.id)
        #expect(set.repos.first { $0.host.repo == "tools" }?.lastActivity == Date(timeIntervalSince1970: 9))
    }

    @Test("Activity from an account that isn't usable on the repo's instance is ignored")
    func unusableActivityAccount() {
        let stranger = HostingAccount(instanceId: HostingInstance.gitHubDotCom.id, login: "marta",
                                      method: .oauth, status: .ok)
        let set = FollowedRepos.merge(local: [], activity: [Self.activity("team/api", stranger, at: 5)],
                                      accounts: [Self.marta, stranger], instances: [.gitHubDotCom, Self.gitlab])
        #expect(set.repos.isEmpty)
    }
}
