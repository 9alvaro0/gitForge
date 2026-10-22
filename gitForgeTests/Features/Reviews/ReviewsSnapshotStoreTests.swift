import Foundation
import Testing
@testable import gitForge

@Suite("Reviews snapshot store")
@MainActor
struct ReviewsSnapshotStoreTests {
    static let octoAccount = UUID()
    static let martaAccount = UUID()

    static let host = RemoteHost(provider: .gitlab, host: "gitlab.example.test", owner: "marta", repo: "tools",
                                 apiBaseURL: URL(string: "https://gitlab.example.test/api/v4"))

    static let repo = ReviewRepo(host: host, accountId: martaAccount, sources: [.local, .activity],
                                 lastActivity: Date(timeIntervalSince1970: 1_700_000_000),
                                 cloneURL: "https://gitlab.example.test/marta/tools.git",
                                 localURL: URL(fileURLWithPath: "/r/marta/tools"))

    static let pull = PullRequest(id: "iid:7", number: 7, title: "Fix the sync", state: .open, authorLogin: "octo",
                                  authorAvatarURL: URL(string: "https://gitlab.example.test/avatars/octo.png"),
                                  sourceBranch: "fix/sync", targetBranch: "main",
                                  webURL: URL(string: "https://gitlab.example.test/marta/tools/-/merge_requests/7"),
                                  createdAt: Date(timeIntervalSince1970: 1_699_000_000),
                                  updatedAt: Date(timeIntervalSince1970: 1_699_500_000.25),
                                  headSha: "abc123")

    static let summary = RemoteRepoSummary(id: "42", name: "tools", fullName: "marta/tools", description: nil,
                                           sshURL: "git@gitlab.example.test:marta/tools.git",
                                           httpsURL: "https://gitlab.example.test/marta/tools.git",
                                           isPrivate: true, defaultBranch: "main")

    static func snapshot(version: Int = ReviewsSnapshot.currentVersion) -> ReviewsSnapshot {
        ReviewsSnapshot(version: version, savedAt: Date(timeIntervalSince1970: 1_700_000_123.5),
                        repos: [repo], pulls: [FollowedRepos.key(host): [pull]],
                        memberships: [martaAccount: MembershipCache(fetchedAt: Date(timeIntervalSince1970: 1_700_000_000),
                                                                    repos: [summary])],
                        logins: [martaAccount: "marta", octoAccount: "octo"])
    }

    static func fileURL(in directory: URL) -> URL {
        directory.appendingPathComponent("reviews.json")
    }

    @Test("Saving and reading again gives the same snapshot, also from a new store")
    func roundTrip() {
        let dir = TemporaryDirectories.make("gitForge-reviews")
        let snapshot = Self.snapshot()
        ReviewsSnapshotStore(directory: dir).save(snapshot)

        #expect(ReviewsSnapshotStore(directory: dir).load() == snapshot)
    }

    @Test("Saving again replaces the previous snapshot")
    func overwrite() {
        let dir = TemporaryDirectories.make("gitForge-reviews")
        let store = ReviewsSnapshotStore(directory: dir)
        store.save(Self.snapshot())
        let empty = ReviewsSnapshot(version: ReviewsSnapshot.currentVersion,
                                    savedAt: Date(timeIntervalSince1970: 1_700_001_000),
                                    repos: [], pulls: [:], memberships: [:], logins: [:])
        store.save(empty)

        #expect(store.load() == empty)
    }

    @Test("Without a file there is nothing to read")
    func missing() {
        let store = ReviewsSnapshotStore(directory: TemporaryDirectories.make("gitForge-reviews"))

        #expect(store.load() == nil)
    }

    @Test("A snapshot from a newer build is not read, and the file stays")
    func newerVersion() throws {
        let dir = TemporaryDirectories.make("gitForge-reviews")
        let store = ReviewsSnapshotStore(directory: dir)
        store.save(Self.snapshot(version: ReviewsSnapshot.currentVersion + 1))
        #expect(store.load() == nil)

        // A newer build may also have changed the shape, which must not matter.
        let future = Data(#"{"version": 2, "inbox": {"rows": []}}"#.utf8)
        try future.write(to: Self.fileURL(in: dir))
        #expect(store.load() == nil)
        #expect(try Data(contentsOf: Self.fileURL(in: dir)) == future)
    }

    @Test("A file that is not JSON is not read, and the file stays")
    func corrupt() throws {
        let dir = TemporaryDirectories.make("gitForge-reviews")
        let store = ReviewsSnapshotStore(directory: dir)
        let garbage = Data([0x00, 0xFF, 0x7B, 0x22, 0x01, 0x80])
        try garbage.write(to: Self.fileURL(in: dir))

        #expect(store.load() == nil)
        #expect(try Data(contentsOf: Self.fileURL(in: dir)) == garbage)
    }

    @Test("JSON of the wrong shape is not read, and the file stays")
    func wrongShape() throws {
        let dir = TemporaryDirectories.make("gitForge-reviews")
        let store = ReviewsSnapshotStore(directory: dir)
        let wrong = Data(#"{"version": 1, "repos": "none"}"#.utf8)
        try wrong.write(to: Self.fileURL(in: dir))

        #expect(store.load() == nil)
        #expect(try Data(contentsOf: Self.fileURL(in: dir)) == wrong)
    }
}
