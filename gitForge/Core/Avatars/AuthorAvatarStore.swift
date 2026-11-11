import Foundation

/// Where avatars may come from for one repository: its host and the token of
/// the account that signs in to it. `nil` when the repository has no
/// connected account; then nothing about avatars ever touches the network.
nonisolated struct AvatarHostAccess: Sendable, Equatable {
    let host: RemoteHost
    let token: String
}

/// The host side of the avatar lookup, so tests can count the calls.
nonisolated protocol AvatarLookupClient: Sendable {
    func avatar(email: String, sha: String, host: RemoteHost, token: String) async throws -> AvatarLookupResult
    func image(at url: URL, host: RemoteHost) async -> Data?
}

extension HostAvatarLookup: AvatarLookupClient {}

/// The avatars of one repository's commit authors (#65), as image data the
/// views decode. Without a connected account the views keep their initials
/// and nothing is requested. With one, each author is looked up once, lazily
/// (only when a row asks), a few at a time, then kept in memory and on disk
/// (`AvatarDiskCache`).
///
/// Not `@Observable` on purpose: each avatar view awaits its own answer, so a
/// picture arriving re-renders that avatar only, never the History table.
@MainActor
final class AuthorAvatarStore {
    /// `rejected`: a token that just got a 401, to renew once.
    typealias Authorize = @MainActor (_ rejected: String?) async -> AvatarHostAccess?

    private let authorize: Authorize
    private let lookup: AvatarLookupClient
    private let disk: AvatarDiskCache?
    private let now: () -> Date

    /// How many host requests run at once.
    static let concurrency = 4
    /// Commits tried for one author before giving up for the session, when
    /// the host doesn't have them (not pushed yet).
    static let commitAttempts = 3
    /// After "no account", the next ask checks again this much later (a
    /// local check), so connecting an account takes effect without a restart.
    static let accessRecheck: TimeInterval = 30
    /// Rate limited, rejected or failing: no requests for this long.
    static let backoff: TimeInterval = 10 * 60
    static let failuresBeforeBackoff = 3

    /// Pictures by normalized email (one repository, so one host).
    private var images: [String: Data] = [:]
    /// Authors known to have no avatar this session.
    private var missing: Set<String> = []
    private var inFlight: [String: Task<Data?, Never>] = [:]
    private var commitTries: [String: Int] = [:]

    private var access: AvatarHostAccess?
    private var accessTask: Task<AvatarHostAccess?, Never>?
    private var accessCheckedAt: Date?
    private var pausedUntil: Date?
    private var consecutiveFailures = 0
    /// Bumped by `reset()`, so a lookup that started before it drops its answer.
    private var generation: UInt64 = 0

    private var running = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(authorize: @escaping Authorize,
         lookup: AvatarLookupClient = HostAvatarLookup(),
         disk: AvatarDiskCache? = AvatarDiskCache(),
         now: @escaping () -> Date = { Date() }) {
        self.authorize = authorize
        self.lookup = lookup
        self.disk = disk
        self.now = now
    }

    /// A store that never has an account: initials only (previews, tests).
    static func offline() -> AuthorAvatarStore {
        AuthorAvatarStore(authorize: { _ in nil }, disk: nil)
    }

    /// The picture already in memory, for a view to show on its first frame
    /// (scrolling back to a row doesn't flash its initials).
    func cachedImage(for email: String) -> Data? {
        images[Self.normalize(email)]
    }

    /// `false` while there's known to be nothing to fetch (no account, checked
    /// recently; or backing off), so a row scrolling in doesn't even wait to ask.
    var mayLoad: Bool {
        if access != nil { return !isPaused }
        if accessTask != nil { return true }
        guard let checked = accessCheckedAt else { return true }
        return now().timeIntervalSince(checked) >= Self.accessRecheck
    }

    /// The author's avatar, or `nil` to keep the initials. `sha`: a commit by
    /// that author, which GitHub needs to find the account.
    func image(email: String, sha: String) async -> Data? {
        let key = Self.normalize(email)
        guard !key.isEmpty else { return nil }
        if let data = images[key] { return data }
        guard !missing.contains(key) else { return nil }
        if let running = inFlight[key] { return await running.value }
        let gen = generation
        let task = Task { await self.load(key: key, sha: sha, gen: gen) }
        inFlight[key] = task
        let data = await task.value
        if gen == generation { inFlight[key] = nil }
        return data
    }

    /// Forgets everything held in memory (repository closed). The disk cache stays.
    func reset() {
        generation &+= 1
        images = [:]
        missing = []
        inFlight.values.forEach { $0.cancel() }
        inFlight = [:]
        commitTries = [:]
        access = nil
        accessTask = nil
        accessCheckedAt = nil
        pausedUntil = nil
        consecutiveFailures = 0
    }

    /// Deletes expired files off the main actor.
    func pruneDiskCache() {
        guard let disk else { return }
        Task.detached(priority: .background) { disk.prune() }
    }

    // MARK: Loading

    private func load(key: String, sha: String, gen: UInt64) async -> Data? {
        // No account, no network: this is the first and only gate.
        guard let access = await currentAccess(), gen == generation else { return nil }
        let diskKey = AvatarDiskCache.key(host: access.host.host, email: key)
        if let disk, let entry = await Self.read(disk, key: diskKey) {
            guard gen == generation else { return nil }
            if let image = entry.image {
                images[key] = image
                return image
            }
            missing.insert(key)
            return nil
        }
        guard !isPaused else { return nil }

        await acquire()
        defer { release() }
        guard gen == generation, !Task.isCancelled, !isPaused else { return nil }

        let result: AvatarLookupResult
        do {
            result = try await lookupWithRenewal(email: key, sha: sha, access: access)
        } catch {
            if gen == generation { note(error) }
            return nil
        }
        guard gen == generation else { return nil }
        consecutiveFailures = 0

        switch result {
        case .found(let url):
            guard let data = await lookup.image(at: url, host: access.host) else {
                // A picture that won't download now may next launch: not stored.
                if gen == generation { missing.insert(key) }
                return nil
            }
            guard gen == generation else { return nil }
            images[key] = data
            persist(AvatarDiskCache.Entry(key: diskKey, avatarURL: url, image: data, fetchedAt: now()))
            return data
        case .none:
            missing.insert(key)
            persist(AvatarDiskCache.Entry(key: diskKey, avatarURL: nil, image: nil, fetchedAt: now()))
            return nil
        case .unknownCommit:
            // Another row with another of the author's commits may find it.
            let tries = (commitTries[key] ?? 0) + 1
            commitTries[key] = tries
            if tries >= Self.commitAttempts { missing.insert(key) }
            return nil
        }
    }

    /// One retry with a renewed token after a 401.
    private func lookupWithRenewal(email: String, sha: String, access: AvatarHostAccess) async throws -> AvatarLookupResult {
        do {
            return try await lookup.avatar(email: email, sha: sha, host: access.host, token: access.token)
        } catch AvatarLookupError.unauthorized {
            guard let renewed = await authorize(access.token) else { throw AvatarLookupError.unauthorized }
            self.access = renewed
            return try await lookup.avatar(email: email, sha: sha, host: renewed.host, token: renewed.token)
        }
    }

    private func note(_ error: Error) {
        switch error {
        case is CancellationError:
            return
        case AvatarLookupError.unauthorized, AvatarLookupError.throttled:
            pausedUntil = now().addingTimeInterval(Self.backoff)
        default:
            consecutiveFailures += 1
            if consecutiveFailures >= Self.failuresBeforeBackoff {
                pausedUntil = now().addingTimeInterval(Self.backoff)
                consecutiveFailures = 0
            }
        }
    }

    private var isPaused: Bool {
        guard let pausedUntil else { return false }
        return now() < pausedUntil
    }

    /// The access, resolved once and shared by every lookup waiting on it;
    /// "no account" is checked again only after `accessRecheck`.
    private func currentAccess() async -> AvatarHostAccess? {
        if let access { return access }
        if let accessTask { return await accessTask.value }
        if let checked = accessCheckedAt, now().timeIntervalSince(checked) < Self.accessRecheck { return nil }
        let gen = generation
        let task = Task { await self.authorize(nil) }
        accessTask = task
        let resolved = await task.value
        guard gen == generation else { return nil }
        accessTask = nil
        accessCheckedAt = now()
        access = resolved
        return resolved
    }

    private func persist(_ entry: AvatarDiskCache.Entry) {
        guard let disk else { return }
        Task.detached(priority: .utility) { disk.store(entry) }
    }

    private nonisolated static func read(_ disk: AvatarDiskCache, key: String) async -> AvatarDiskCache.Entry? {
        await Task.detached(priority: .userInitiated) { disk.entry(for: key) }.value
    }

    nonisolated static func normalize(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    // MARK: Concurrency limit

    private func acquire() async {
        if running < Self.concurrency {
            running += 1
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    /// Hands the slot straight to the next waiter, if any.
    private func release() {
        if waiters.isEmpty {
            running -= 1
        } else {
            waiters.removeFirst().resume()
        }
    }
}

extension AccountPullRequestAuth {
    /// The avatars' access for a repository: its `origin` host and the token
    /// of its account, never asking the user to pick one. `nil` (and no
    /// request of any kind) when the host isn't a declared instance or no
    /// usable account signs in to it.
    func avatarAccess(cli: GitCLI, repoPath: String) -> AuthorAvatarStore.Authorize {
        { [weak self] rejected in
            guard let self, let host = await self.remoteHost(cli) else { return nil }
            guard case .token(let token) = await self.access(host: host, repoPath: repoPath,
                                                            rejected: rejected, interactive: false) else { return nil }
            return AvatarHostAccess(host: host, token: token)
        }
    }
}
