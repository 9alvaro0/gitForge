import Foundation
import Testing
@testable import gitForge

/// Records the URLs it was asked about and answers reachable.
private final class ProbeLog: @unchecked Sendable {
    private let lock = NSLock()
    private var urls: [String] = []
    var asked: [String] { lock.withLock { urls } }
    func record(_ url: String) { lock.withLock { urls.append(url) } }
}

@Suite("Clone sheet model", .serialized)
@MainActor
struct CloneSheetModelTests {

    private func store() -> AccountStore {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gitForge-clonesheet-\(UUID().uuidString)")
        return AccountStore(directory: dir, secrets: InMemoryAccountSecretStore())
    }

    private func model(_ store: AccountStore, log: ProbeLog = ProbeLog()) -> CloneSheetModel {
        CloneSheetModel(store: store, parentDirectory: "/tmp/gitforge-none-\(UUID().uuidString)",
                        debounce: .milliseconds(30),
                        probe: { url in log.record(url); return .reachable(defaultBranch: "main") })
    }

    @Test("Typing fast: only the last URL is probed and shown")
    func lastWins() async {
        let log = ProbeLog()
        let m = model(store(), log: log)
        m.url = "https://github.com/octo/one.git"
        let first = Task { await m.urlChanged() }
        m.url = "https://github.com/octo/two.git"
        let second = Task { await m.urlChanged() }
        await first.value
        await second.value
        #expect(log.asked == ["https://github.com/octo/two.git"])
        #expect(m.probe == .done(.reachable(defaultBranch: "main")))
    }

    @Test("An empty URL goes back to idle without probing")
    func empty() async {
        let log = ProbeLog()
        let m = model(store(), log: log)
        m.url = "   "
        await m.urlChanged()
        #expect(m.probe == .idle)
        #expect(log.asked.isEmpty)
    }

    @Test("The summary names the provider, the repo and the account that will sign")
    func summary() throws {
        let s = store()
        let profile = UUID()
        var octo = HostingAccount(instanceId: HostingInstance.gitHubDotCom.id, login: "octo", method: .oauth, status: .ok)
        octo.linkedProfileId = profile
        try s.addAccount(octo, secret: AccountSecret(accessToken: "test-a"))
        let m = model(s)
        m.url = "https://github.com/octo/app.git"
        #expect(m.remoteSummary == "GitHub · octo/app · via octo")
        #expect(m.suggestedProfileId == profile)
        m.url = "git@github.com:octo/app.git"
        #expect(m.remoteSummary == "GitHub · octo/app · SSH")
        m.url = "https://example.org/x/y.git"
        #expect(m.remoteSummary == nil)
    }

    @Test("An account linked to a deleted profile suggests none")
    func deletedProfile() throws {
        let s = store()
        var octo = HostingAccount(instanceId: HostingInstance.gitHubDotCom.id, login: "octo", method: .oauth, status: .ok)
        octo.linkedProfileId = UUID()
        try s.addAccount(octo, secret: AccountSecret(accessToken: "test-a"))
        let m = CloneSheetModel(store: s, parentDirectory: "/tmp/gitforge-none-\(UUID().uuidString)",
                                probe: { _ in .reachable(defaultBranch: "main") }, profileExists: { _ in false })
        m.url = "https://github.com/octo/app.git"
        #expect(m.suggestedProfileId == nil)
        #expect(m.profileId == nil)
    }

    @Test("Deleting a profile unlinks the accounts that pointed at it")
    func unlinkProfile() throws {
        let s = store()
        let profile = UUID()
        var octo = HostingAccount(instanceId: HostingInstance.gitHubDotCom.id, login: "octo", method: .oauth, status: .ok)
        octo.linkedProfileId = profile
        try s.addAccount(octo, secret: AccountSecret(accessToken: "test-a"))
        s.unlinkProfile(profile)
        #expect(s.accounts[0].linkedProfileId == nil)
    }

    @Test("A repo picked from My repos is cloned with its account while the URL stays")
    func picked() throws {
        let m = model(store())
        let id = UUID()
        m.pick(RemoteRepoSummary(id: "1", name: "app", fullName: "octo/app", description: nil, sshURL: nil,
                                 httpsURL: "https://github.com/octo/app.git", isPrivate: true, defaultBranch: "main"),
               accountId: id)
        #expect(m.url == "https://github.com/octo/app.git")
        #expect(m.accountIdForClone == id)
        m.url = "https://github.com/octo/other.git"
        #expect(m.accountIdForClone == nil)
    }

    @Test("Clone needs a URL and a free destination, not a passing probe")
    func canClone() {
        let m = model(store())
        #expect(!m.canClone)
        m.url = "https://github.com/octo/app.git"
        #expect(m.destination.hasSuffix("/app"))
        #expect(m.canClone)
        m.destination = NSTemporaryDirectory()
        #expect(!m.canClone)
    }

    @Test("Choose… before the URL picks the parent; the folder name still follows the URL")
    func chooseParentFirst() {
        let m = model(store())
        m.chooseParent("/tmp/parent")
        #expect(m.destination == "/tmp/parent/repo")
        m.url = "https://github.com/octo/gitForge.git"
        #expect(m.destination == "/tmp/parent/gitForge")
        m.url = "https://github.com/octo/other.git"
        #expect(m.destination == "/tmp/parent/other")
    }

    @Test("The destination says why Clone is off, or that its parent will be created")
    func destinationHint() {
        let m = model(store())
        m.url = "https://github.com/octo/app.git"
        #expect(m.destinationHint == "Parent folder will be created")
        m.destination = NSTemporaryDirectory()
        #expect(m.destinationHint == "Already exists — choose another folder")
        m.destination = NSTemporaryDirectory() + "gitforge-new-\(UUID().uuidString)"
        #expect(m.destinationHint == nil)
    }

    @Test("A new URL shows Checking… right away, never the previous URL's result")
    func noStaleResult() async {
        let m = model(store())
        m.url = "https://github.com/octo/one.git"
        await m.urlChanged()
        #expect(m.probe == .done(.reachable(defaultBranch: "main")))
        m.url = "https://github.com/octo/two.git"
        let pending = Task { await m.urlChanged() }
        await Task.yield()
        #expect(m.probe == .checking)
        await pending.value
    }

    @Test("VoiceOver hears the reachability badge's text")
    func probeDescription() {
        #expect(CloneSheet.probeDescription(.idle) == nil)
        #expect(CloneSheet.probeDescription(.checking) == "Checking…")
        #expect(CloneSheet.probeDescription(.done(.reachable(defaultBranch: "main"))) == "Reachable")
        #expect(CloneSheet.probeDescription(.done(.unreachable(.network))) == "Can't reach · offline")
    }
}
