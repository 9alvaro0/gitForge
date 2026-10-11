import Foundation
import Testing
@testable import gitForge

@Suite("RepoAccountMenuModel")
struct RepoAccountMenuModelTests {
    static let personal = HostingAccount(instanceId: HostingInstance.gitHubDotCom.id, login: "personal", method: .oauth, status: .ok)
    static let work = HostingAccount(instanceId: HostingInstance.gitHubDotCom.id, login: "work", method: .oauth, status: .ok)
    static let origin = GitRemoteURL(name: "origin", url: "https://github.com/some-org/app.git")

    private func sections(_ accounts: [HostingAccount], remotes: [GitRemoteURL] = [origin],
                          assignments: [String: [String: RepoAccountChoice]] = [:]) -> [RepoAccountSection] {
        RepoAccountMenuModel.sections(remotes: remotes, repoPath: "/r/app", activeProfileId: nil,
                                      instances: HostingInstance.builtIns, accounts: accounts, assignments: assignments)
    }

    @Test("Two accounts, nothing chosen: Choose…, automatic asks")
    func ambiguous() throws {
        let section = try #require(sections([Self.personal, Self.work]).first)
        #expect(section.title == "Hosting account · origin")
        #expect(section.current == "Choose…")
        #expect(section.entries == [
            .automatic(label: "Automatic (ask)", checked: true),
            .account(id: Self.personal.id, label: "personal", checked: false),
            .account(id: Self.work.id, label: "work", checked: false),
            .system(checked: false),
            .connect(instanceId: HostingInstance.gitHubDotCom.id),
        ])
    }

    @Test("A chosen account is current and checked; automatic says what it would pick")
    func chosen() {
        let section = sections([Self.personal], assignments: ["/r/app": ["origin": .account(Self.personal.id)]])[0]
        #expect(section.current == "personal @ github.com")
        #expect(section.entries.first == .automatic(label: "Automatic (personal)", checked: false))
        #expect(section.entries.contains(.account(id: Self.personal.id, label: "personal", checked: true)))
    }

    @Test("System credentials, chosen or with no usable account")
    func system() {
        let chosen = sections([Self.personal], assignments: ["/r/app": ["origin": .system]])[0]
        #expect(chosen.current == "System credentials")
        #expect(chosen.entries.contains(.system(checked: true)))
        let revoked = HostingAccount(instanceId: HostingInstance.gitHubDotCom.id, login: "old", method: .personalToken,
                                     status: .needsAttention(.revoked))
        let none = sections([revoked])[0]
        #expect(none.current == "System credentials")
        #expect(none.entries.first == .automatic(label: "Automatic (system credentials)", checked: true))
    }

    @Test("SSH remotes and unknown hosts get no section")
    func noSection() {
        let remotes = [GitRemoteURL(name: "origin", url: "git@github.com:me/app.git"),
                       GitRemoteURL(name: "fork", url: "https://git.unknown.test/me/app.git")]
        #expect(sections([Self.personal], remotes: remotes).isEmpty)
    }

    @Test("Remotes and their URLs, from git")
    func remotesFromGit() async throws {
        let repo = try GitTestRepo()
        defer { repo.remove() }
        try repo.git("remote", "add", "origin", "https://github.com/me/app.git")
        try repo.git("remote", "add", "upstream", "git@github.com:org/app.git")
        #expect(await repo.cli.remotesWithURLs() == [
            GitRemoteURL(name: "origin", url: "https://github.com/me/app.git"),
            GitRemoteURL(name: "upstream", url: "git@github.com:org/app.git"),
        ])
    }
}
