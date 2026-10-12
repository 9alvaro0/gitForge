import Foundation
import Testing
@testable import gitForge

/// Records which remotes git commands were signed for. Hands out no
/// credential, so the commands run exactly as without accounts.
private final class RecordingCredentials: GitCredentialProvider, @unchecked Sendable {
    private let accounts: [String: UUID]
    private let needsChoice: Set<String>
    private let lock = NSLock()
    private var remotes: [String] = []

    init(accounts: [String: UUID] = [:], needsChoice: Set<String> = []) {
        self.accounts = accounts
        self.needsChoice = needsChoice
    }

    var signedRemotes: [String] { lock.withLock { remotes } }

    func signer(remoteURL: String, remoteName: String, repoPath: String) async -> GitSigner {
        if needsChoice.contains(remoteURL) { return .needsChoice }
        return accounts[remoteURL].map(GitSigner.account) ?? .none
    }

    func withCredential<T: Sendable>(remoteURL: String, remoteName: String, repoPath: String,
                                     _ operation: @Sendable (GitCredential?) async throws -> T) async throws -> T {
        lock.withLock { remotes.append(remoteName) }
        return try await operation(nil)
    }
}

@Suite("GitCLI — network commands signed per remote")
struct GitCLICredentialRoutingTests {
    /// A work repo with two remotes, `origin` and `upstream`: bare repos that
    /// each hold the work repo's first commit on `main`.
    private func makeRepos() throws -> (work: GitTestRepo, origin: GitTestRepo, upstream: GitTestRepo) {
        let origin = try GitTestRepo(bare: true)
        let upstream = try GitTestRepo(bare: true)
        let work = try GitTestRepo()
        try work.commit("first")
        for (name, bare) in [("origin", origin), ("upstream", upstream)] {
            try work.git("remote", "add", name, bare.url.path)
            try work.git("push", "-q", name, "main")
        }
        return (work, origin, upstream)
    }

    private func hasRef(_ repo: GitTestRepo, _ ref: String) -> Bool {
        (try? repo.git("rev-parse", "--verify", "-q", ref)) != nil
    }

    @Test("fetch --all with one account: a single run, signed for the remote that has it")
    func fetchAllOneAccount() async throws {
        let (work, origin, upstream) = try makeRepos()
        let account = UUID()
        let recorder = RecordingCredentials(accounts: [origin.url.path: account, upstream.url.path: account])
        try await GitCLI(workingDirectory: work.url, credentials: recorder).fetchAll()
        #expect(recorder.signedRemotes == ["origin"])
        #expect(hasRef(work, "refs/remotes/upstream/main"))
    }

    @Test("fetch --all with two accounts: one run per remote, each signed for its own")
    func fetchAllTwoAccounts() async throws {
        let (work, origin, upstream) = try makeRepos()
        let recorder = RecordingCredentials(accounts: [origin.url.path: UUID(), upstream.url.path: UUID()])
        try await GitCLI(workingDirectory: work.url, credentials: recorder).fetchAll()
        #expect(recorder.signedRemotes == ["origin", "upstream"])
        #expect(hasRef(work, "refs/remotes/origin/main"))
        #expect(hasRef(work, "refs/remotes/upstream/main"))
    }

    @Test("fetch --all where a same-host remote has no account: split, so that remote keeps the system helper")
    func fetchAllMixedSameHost() async throws {
        let (work, origin, _) = try makeRepos()
        let recorder = RecordingCredentials(accounts: [origin.url.path: UUID()])
        try await GitCLI(workingDirectory: work.url, credentials: recorder).fetchAll()
        #expect(recorder.signedRemotes == ["origin", "upstream"])
        #expect(hasRef(work, "refs/remotes/upstream/main"))
    }

    @Test("A remote with skipFetchAll is left out of the per-remote runs, as fetch --all does")
    func fetchAllSkipsSkipFetchAll() async throws {
        let (work, origin, upstream) = try makeRepos()
        try work.git("config", "remote.upstream.skipFetchAll", "true")
        let recorder = RecordingCredentials(accounts: [origin.url.path: UUID(), upstream.url.path: UUID()])
        try await GitCLI(workingDirectory: work.url, credentials: recorder).fetchAll()
        #expect(recorder.signedRemotes == ["origin"])
    }

    @Test("skipFetchAll lines: only true values, names with dots kept whole")
    func skipFetchAllParsing() {
        let output = "remote.upstream.skipfetchall true\nremote.my.fork.skipfetchall true\nremote.origin.skipfetchall false\n"
        #expect(GitCLI.skipFetchAllRemotes(output) == ["upstream", "my.fork"])
    }

    @Test("A remote that needs a choice is fetched on its own, so the sheet can show")
    func fetchAllNeedsChoice() async throws {
        let (work, _, upstream) = try makeRepos()
        let recorder = RecordingCredentials(needsChoice: [upstream.url.path])
        try await GitCLI(workingDirectory: work.url, credentials: recorder).fetchAll()
        #expect(recorder.signedRemotes == ["origin", "upstream"])
    }

    @Test("fetch --all with no accounts: nothing is signed")
    func fetchAllNoAccounts() async throws {
        let (work, _, _) = try makeRepos()
        let recorder = RecordingCredentials()
        try await GitCLI(workingDirectory: work.url, credentials: recorder).fetchAll()
        #expect(recorder.signedRemotes.isEmpty)
        #expect(hasRef(work, "refs/remotes/upstream/main"))
    }

    @Test("push, fetch and the tag pushes are signed for the remote they talk to")
    func pushAndTags() async throws {
        let (work, _, _) = try makeRepos()
        try work.git("tag", "v1")
        let recorder = RecordingCredentials()
        let cli = GitCLI(workingDirectory: work.url, credentials: recorder)
        try await cli.push(setUpstream: true, remote: "upstream", branch: "main")
        try await cli.fetch(remote: "upstream")
        try await cli.pushTag(name: "v1", remote: "origin")
        try await cli.pushDeleteTag(name: "v1", remote: "origin")
        try await cli.pushAllTags(remote: "upstream")
        #expect(recorder.signedRemotes == ["upstream", "upstream", "origin", "origin", "upstream"])
    }

    @Test("pull is signed for the current branch's remote")
    func pullUsesBranchRemote() async throws {
        let (work, _, _) = try makeRepos()
        try work.git("branch", "-q", "--set-upstream-to=upstream/main")
        let recorder = RecordingCredentials()
        try await GitCLI(workingDirectory: work.url, credentials: recorder).pull(ffOnly: true)
        #expect(recorder.signedRemotes == ["upstream"])
    }
}
