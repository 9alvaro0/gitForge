import Foundation
import Testing
@testable import gitForge

/// A host lookup that answers from the test and records every call.
final class SpyAvatarLookup: AvatarLookupClient, @unchecked Sendable {
    struct Call: Equatable {
        let email: String
        let sha: String
        let token: String
    }

    private let lock = NSLock()
    private var calls: [Call] = []
    private var imageCalls: [URL] = []
    private var running = 0
    private var peak = 0
    /// Answers by email; anything else has no avatar.
    var answers: [String: Result<AvatarLookupResult, AvatarLookupError>] = [:]
    /// Answers by token, over `answers` (a rejected token).
    var tokenAnswers: [String: AvatarLookupError] = [:]
    var imageData: Data? = Data([0x89, 0x50, 0x4E, 0x47])
    /// Holds every lookup until opened.
    var gate: AsyncGate?

    var lookups: [Call] { lock.withLock { calls } }
    var downloads: [URL] { lock.withLock { imageCalls } }
    var peakConcurrency: Int { lock.withLock { peak } }
    var requestCount: Int { lock.withLock { calls.count + imageCalls.count } }

    func avatar(email: String, sha: String, host: RemoteHost, token: String) async throws -> AvatarLookupResult {
        let (answer, rejected, gate) = lock.withLock {
            calls.append(Call(email: email, sha: sha, token: token))
            running += 1
            peak = max(peak, running)
            return (answers[email], tokenAnswers[token], self.gate)
        }
        await gate?.wait()
        lock.withLock { running -= 1 }
        if let rejected { throw rejected }
        return try (answer ?? .success(.none)).get()
    }

    func image(at url: URL, host: RemoteHost) async -> Data? {
        lock.withLock {
            imageCalls.append(url)
            return imageData
        }
    }
}

@Suite("AuthorAvatarStore")
@MainActor
struct AuthorAvatarStoreTests {
    nonisolated static let host = RemoteHost(provider: .github, host: "github.com", owner: "octo", repo: "app")
    nonisolated static let avatarURL = URL(string: "https://avatars.githubusercontent.com/u/7?s=64")!

    /// Counts the access checks and hands out `access`.
    @MainActor
    final class Access {
        var access: AvatarHostAccess?
        var renewed: AvatarHostAccess?
        var calls: [String?] = []
        init(_ access: AvatarHostAccess?) { self.access = access }
        var authorize: AuthorAvatarStore.Authorize {
            { [self] rejected in
                calls.append(rejected)
                if rejected != nil { return renewed }
                return access
            }
        }
    }

    final class Clock: @unchecked Sendable {
        private let lock = NSLock()
        private var value = Date(timeIntervalSince1970: 1_800_000_000)
        var now: Date { lock.withLock { value } }
        func advance(_ seconds: TimeInterval) { lock.withLock { value = value.addingTimeInterval(seconds) } }
    }

    private func diskCache(_ clock: Clock = Clock()) -> AvatarDiskCache {
        AvatarDiskCache(directory: TemporaryDirectories.make("gitForge-avatar-store"), now: { clock.now })
    }

    private func signedIn() -> Access { Access(AvatarHostAccess(host: Self.host, token: "test-token")) }

    // MARK: No account, no network

    @Test("Without an account nothing is requested, read or written, and the initials stay")
    func noAccountNoNetwork() async throws {
        let spy = SpyAvatarLookup()
        let access = Access(nil)
        // A fixed clock: on a loaded runner the three lookups can be more than
        // `accessRecheck` apart in real time, and "no account" would be asked again.
        let clock = Clock()
        let disk = diskCache(clock)
        let store = AuthorAvatarStore(authorize: access.authorize, lookup: spy, disk: disk, now: { clock.now })
        for (index, email) in ["ana@forge.dev", "luis@forge.dev", "12345+ana@users.noreply.github.com"].enumerated() {
            #expect(await store.image(email: email, sha: "abc\(index)") == nil)
        }
        #expect(spy.requestCount == 0)
        #expect(!FileManager.default.fileExists(atPath: disk.directory.path))
        // "No account" is remembered for a while instead of asked per row.
        #expect(access.calls.count == 1)
    }

    @Test("Views are told not to ask while it's known there's no account, and again once it may have changed")
    func mayLoad() async throws {
        let clock = Clock()
        let store = AuthorAvatarStore(authorize: Access(nil).authorize, lookup: SpyAvatarLookup(), disk: nil, now: { clock.now })
        #expect(store.mayLoad)
        _ = await store.image(email: "ana@forge.dev", sha: "a")
        #expect(!store.mayLoad)
        clock.advance(AuthorAvatarStore.accessRecheck + 1)
        #expect(store.mayLoad)

        let throttled = SpyAvatarLookup()
        throttled.answers["a@forge.dev"] = .failure(.throttled)
        let signed = AuthorAvatarStore(authorize: signedIn().authorize, lookup: throttled, disk: nil, now: { clock.now })
        _ = await signed.image(email: "a@forge.dev", sha: "1")
        #expect(!signed.mayLoad)
    }

    @Test("Through the real account resolution: a GitHub repo with no account connected makes no request")
    func noAccountThroughAccountResolution() async throws {
        let repo = try await GitTestRepo.make { try $0.commit("base", files: ["a.txt": "1"]) }
        defer { repo.remove() }
        try await repo.gitAsync("remote", "add", "origin", "https://github.com/octo/app.git")
        let secrets = InMemoryAccountSecretStore()
        let accounts = AccountStore(directory: TemporaryDirectories.make("gitForge-avatar-accounts"), secrets: secrets,
                                    clientIds: OAuthClientIDs(gitHub: "gh", gitLab: "gl"))
        let refreshes = CallCount()
        let refresher = TokenRefresher(secrets: secrets, makeClient: { _ in
            refreshes.add()
            return FakeAuthClient()
        }, onRefreshRejected: { _ in })
        let auth = AccountPullRequestAuth(store: accounts, refresher: refresher)
        let spy = SpyAvatarLookup()
        let store = AuthorAvatarStore(authorize: auth.avatarAccess(cli: repo.cli, repoPath: repo.url.path),
                                      lookup: spy, disk: diskCache())

        #expect(await store.image(email: "test@example.com", sha: "abc") == nil)
        #expect(spy.requestCount == 0)
        #expect(refreshes.value == 0)
    }

    @Test("With an account, the repo's host and token reach the lookup")
    func accountResolution() async throws {
        let repo = try await GitTestRepo.make { try $0.commit("base", files: ["a.txt": "1"]) }
        defer { repo.remove() }
        try await repo.gitAsync("remote", "add", "origin", "git@github.com:octo/app.git")
        let secrets = InMemoryAccountSecretStore()
        let accounts = AccountStore(directory: TemporaryDirectories.make("gitForge-avatar-accounts"), secrets: secrets,
                                    clientIds: OAuthClientIDs(gitHub: "gh", gitLab: "gl"))
        try accounts.addAccount(HostingAccount(instanceId: HostingInstance.gitHubDotCom.id, login: "octo", method: .oauth, status: .ok),
                                secret: AccountSecret(accessToken: "test-oauth"))
        let refresher = TokenRefresher(secrets: secrets, makeClient: { _ in FakeAuthClient() }, onRefreshRejected: { _ in })
        let auth = AccountPullRequestAuth(store: accounts, refresher: refresher)
        let access = await auth.avatarAccess(cli: repo.cli, repoPath: repo.url.path)(nil)
        #expect(access?.token == "test-oauth")
        #expect(access?.host.host == "github.com" && access?.host.slug == "octo/app")
    }

    // MARK: Loading

    @Test("An avatar is looked up once, then served from memory")
    func memoryCache() async throws {
        let spy = SpyAvatarLookup()
        spy.answers["ana@forge.dev"] = .success(.found(Self.avatarURL))
        let store = AuthorAvatarStore(authorize: signedIn().authorize, lookup: spy, disk: diskCache())
        let first = await store.image(email: "Ana@Forge.dev", sha: "abc")
        #expect(first == spy.imageData)
        #expect(await store.image(email: "ana@forge.dev", sha: "def") == spy.imageData)
        #expect(store.cachedImage(for: " ANA@forge.dev") == spy.imageData)
        #expect(spy.lookups == [.init(email: "ana@forge.dev", sha: "abc", token: "test-token")])
        #expect(spy.downloads == [Self.avatarURL])
    }

    @Test("Many rows asking for the same author at once make one lookup")
    func deduplicates() async throws {
        let spy = SpyAvatarLookup()
        spy.answers["ana@forge.dev"] = .success(.found(Self.avatarURL))
        let gate = AsyncGate()
        spy.gate = gate
        let store = AuthorAvatarStore(authorize: signedIn().authorize, lookup: spy, disk: nil)
        let tasks = (0..<5).map { index in Task { await store.image(email: "ana@forge.dev", sha: "sha\(index)") } }
        await gate.waiting()
        gate.open()
        for task in tasks { #expect(await task.value == spy.imageData) }
        #expect(spy.lookups.count == 1)
    }

    @Test("At most a few lookups run at once")
    func concurrencyLimit() async throws {
        let spy = SpyAvatarLookup()
        let gate = AsyncGate()
        spy.gate = gate
        let store = AuthorAvatarStore(authorize: signedIn().authorize, lookup: spy, disk: nil)
        let tasks = (0..<12).map { index in Task { await store.image(email: "dev\(index)@forge.dev", sha: "sha\(index)") } }
        await waitUntil { spy.lookups.count >= AuthorAvatarStore.concurrency }
        // Give the rest a chance to (wrongly) start.
        for _ in 0..<20 { await Task.yield() }
        #expect(spy.lookups.count == AuthorAvatarStore.concurrency)
        gate.open()
        for task in tasks { _ = await task.value }
        #expect(spy.lookups.count == 12)
        #expect(spy.peakConcurrency <= AuthorAvatarStore.concurrency)
    }

    @Test("The disk cache answers the next launch without asking the host")
    func diskCacheAcrossLaunches() async throws {
        let clock = Clock()
        let disk = diskCache(clock)
        let spy = SpyAvatarLookup()
        spy.answers["ana@forge.dev"] = .success(.found(Self.avatarURL))
        spy.answers["luis@forge.dev"] = .success(.none)
        let first = AuthorAvatarStore(authorize: signedIn().authorize, lookup: spy, disk: disk, now: { clock.now })
        _ = await first.image(email: "ana@forge.dev", sha: "a")
        _ = await first.image(email: "luis@forge.dev", sha: "b")
        await waitUntil { disk.entry(for: AvatarDiskCache.key(host: "github.com", email: "luis@forge.dev")) != nil
            && disk.entry(for: AvatarDiskCache.key(host: "github.com", email: "ana@forge.dev")) != nil }

        let quiet = SpyAvatarLookup()
        let second = AuthorAvatarStore(authorize: signedIn().authorize, lookup: quiet, disk: disk, now: { clock.now })
        #expect(await second.image(email: "ana@forge.dev", sha: "a") == spy.imageData)
        #expect(await second.image(email: "luis@forge.dev", sha: "b") == nil)
        #expect(quiet.requestCount == 0)

        // Two days later "no avatar" has expired and is asked again; the picture hasn't.
        clock.advance(2 * 24 * 3600)
        let third = AuthorAvatarStore(authorize: signedIn().authorize, lookup: quiet, disk: disk, now: { clock.now })
        #expect(await third.image(email: "ana@forge.dev", sha: "a") == spy.imageData)
        _ = await third.image(email: "luis@forge.dev", sha: "b")
        #expect(quiet.lookups.map(\.email) == ["luis@forge.dev"])
    }

    @Test("No avatar is remembered: the host isn't asked again this session")
    func missingRemembered() async throws {
        let spy = SpyAvatarLookup()
        let store = AuthorAvatarStore(authorize: signedIn().authorize, lookup: spy, disk: nil)
        #expect(await store.image(email: "x@forge.dev", sha: "a") == nil)
        #expect(await store.image(email: "x@forge.dev", sha: "b") == nil)
        #expect(spy.lookups.count == 1)
        #expect(spy.downloads.isEmpty)
    }

    @Test("A commit the host doesn't have: other commits are tried, a few times at most")
    func unknownCommit() async throws {
        let spy = SpyAvatarLookup()
        spy.answers["wip@forge.dev"] = .success(.unknownCommit)
        let store = AuthorAvatarStore(authorize: signedIn().authorize, lookup: spy, disk: nil)
        for index in 0..<6 { _ = await store.image(email: "wip@forge.dev", sha: "local\(index)") }
        #expect(spy.lookups.map(\.sha) == (0..<AuthorAvatarStore.commitAttempts).map { "local\($0)" })
    }

    @Test("A rejected token is renewed once and the lookup retried")
    func renewsToken() async throws {
        let spy = SpyAvatarLookup()
        spy.tokenAnswers["test-token"] = .unauthorized
        spy.answers["ana@forge.dev"] = .success(.found(Self.avatarURL))
        let access = signedIn()
        access.renewed = AvatarHostAccess(host: Self.host, token: "test-renewed")
        let store = AuthorAvatarStore(authorize: access.authorize, lookup: spy, disk: nil)
        #expect(await store.image(email: "ana@forge.dev", sha: "a") == spy.imageData)
        #expect(spy.lookups.map(\.token) == ["test-token", "test-renewed"])
        #expect(access.calls == [nil, "test-token"])
        // The renewed token is kept.
        _ = await store.image(email: "luis@forge.dev", sha: "b")
        #expect(spy.lookups.last?.token == "test-renewed")
    }

    @Test("Rate limited: no more requests until the back-off passes")
    func backsOff() async throws {
        let clock = Clock()
        let spy = SpyAvatarLookup()
        spy.answers["a@forge.dev"] = .failure(.throttled)
        let store = AuthorAvatarStore(authorize: signedIn().authorize, lookup: spy, disk: nil, now: { clock.now })
        _ = await store.image(email: "a@forge.dev", sha: "1")
        _ = await store.image(email: "b@forge.dev", sha: "2")
        #expect(spy.lookups.count == 1)
        clock.advance(AuthorAvatarStore.backoff + 1)
        _ = await store.image(email: "b@forge.dev", sha: "2")
        #expect(spy.lookups.count == 2)
    }

    @Test("Repeated failures back off too; a single one doesn't")
    func failuresBackOff() async throws {
        let spy = SpyAvatarLookup()
        for index in 0..<5 { spy.answers["f\(index)@forge.dev"] = .failure(.failed) }
        let store = AuthorAvatarStore(authorize: signedIn().authorize, lookup: spy, disk: nil)
        for index in 0..<5 { _ = await store.image(email: "f\(index)@forge.dev", sha: "\(index)") }
        #expect(spy.lookups.count == AuthorAvatarStore.failuresBeforeBackoff)
    }

    @Test("A picture that won't download keeps the initials and isn't stored")
    func downloadFails() async throws {
        let disk = diskCache()
        let spy = SpyAvatarLookup()
        spy.imageData = nil
        spy.answers["ana@forge.dev"] = .success(.found(Self.avatarURL))
        let store = AuthorAvatarStore(authorize: signedIn().authorize, lookup: spy, disk: disk)
        #expect(await store.image(email: "ana@forge.dev", sha: "a") == nil)
        #expect(disk.entry(for: AvatarDiskCache.key(host: "github.com", email: "ana@forge.dev")) == nil)
    }

    @Test("Connecting an account later is picked up after the recheck interval")
    func accountConnectedLater() async throws {
        let clock = Clock()
        let spy = SpyAvatarLookup()
        let access = Access(nil)
        let store = AuthorAvatarStore(authorize: access.authorize, lookup: spy, disk: nil, now: { clock.now })
        _ = await store.image(email: "ana@forge.dev", sha: "a")
        access.access = AvatarHostAccess(host: Self.host, token: "test-token")
        _ = await store.image(email: "ana@forge.dev", sha: "a")
        #expect(spy.lookups.isEmpty)
        clock.advance(AuthorAvatarStore.accessRecheck + 1)
        _ = await store.image(email: "ana@forge.dev", sha: "a")
        #expect(spy.lookups.count == 1)
    }

    @Test("Reset forgets what's in memory")
    func reset() async throws {
        let spy = SpyAvatarLookup()
        spy.answers["ana@forge.dev"] = .success(.found(Self.avatarURL))
        let store = AuthorAvatarStore(authorize: signedIn().authorize, lookup: spy, disk: nil)
        _ = await store.image(email: "ana@forge.dev", sha: "a")
        store.reset()
        #expect(store.cachedImage(for: "ana@forge.dev") == nil)
        _ = await store.image(email: "ana@forge.dev", sha: "a")
        #expect(spy.lookups.count == 2)
    }

    @Test("An empty email never asks")
    func emptyEmail() async throws {
        let spy = SpyAvatarLookup()
        let access = signedIn()
        let store = AuthorAvatarStore(authorize: access.authorize, lookup: spy, disk: nil)
        #expect(await store.image(email: "  ", sha: "a") == nil)
        #expect(spy.requestCount == 0 && access.calls.isEmpty)
    }
}
