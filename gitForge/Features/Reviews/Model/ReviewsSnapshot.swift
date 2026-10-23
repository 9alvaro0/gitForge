import Foundation
import os

/// The repos an account belongs to, as of `fetchedAt`. Lets the inbox follow
/// repos without asking the hosting platform again on every launch.
nonisolated struct MembershipCache: Codable, Equatable, Sendable {
    var fetchedAt: Date
    var repos: [RemoteRepoSummary]
    /// The read ended on an empty page before the page cap, so `repos` is
    /// everything the account belongs to; `false` when it stopped at the cap
    /// and there may be more. `nil` in a snapshot saved before this was
    /// recorded (optional so those still decode): `ReviewsStore.isComplete(_:)`
    /// reads it as complete when the list is shorter than the cap allows.
    var isComplete: Bool? = nil
}

/// What a rename lookup found for a clone whose `origin` matched no repo the
/// accounts belong to: the repo's current path, or `nil` when the server has no
/// such repo any more (a 404). Cached for 24 h so the inbox doesn't ask again
/// on every refresh.
nonisolated struct RepoLookup: Codable, Equatable, Sendable {
    var fetchedAt: Date
    var currentPath: String?
}

/// What the Reviews inbox knew when it last loaded: the repos it follows, their
/// open pull requests, the cached memberships and each account's login. Kept in
/// `reviews.json` so the inbox and ⌘K have data at launch and offline.
nonisolated struct ReviewsSnapshot: Codable, Equatable, Sendable {
    /// The newest layout this build reads and the one it writes.
    static let currentVersion = 1

    var version: Int
    var savedAt: Date
    var repos: [ReviewRepo]
    /// Open pull requests by `ReviewRepo.id`.
    var pulls: [String: [PullRequest]]
    /// By account id.
    var memberships: [UUID: MembershipCache]
    /// The user's login on each account, by account id.
    var logins: [UUID: String]
    /// Rename lookups by the clone's `FollowedRepos.key`. Optional with a `nil`
    /// default so a snapshot saved by R2, which has none, still decodes at the
    /// same version.
    var lookups: [String: RepoLookup]? = nil
}

/// Reads and writes the last `ReviewsSnapshot` as `reviews.json`, next to
/// `accounts.json` in Application Support. It is only a cache: a file it can't
/// read is left where it is (the next save replaces it) and reads as "no
/// snapshot".
@MainActor
final class ReviewsSnapshotStore {
    private static let logger = Logger(subsystem: "com.warwarelabs.gitForge", category: "reviews")

    private let fileURL: URL

    private struct VersionProbe: Decodable { let version: Int }

    init(directory: URL? = nil) {
        let dir = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!.appendingPathComponent("gitForge", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("reviews.json")
    }

    /// `nil` when there is no file, it can't be read, or a newer build wrote it.
    func load() -> ReviewsSnapshot? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        do {
            let data = try Data(contentsOf: fileURL)
            // Read the version alone first: a newer build may have changed the shape.
            let version = try JSONDecoder().decode(VersionProbe.self, from: data).version
            guard version <= ReviewsSnapshot.currentVersion else {
                Self.logger.error("reviews.json version \(version, privacy: .public) is newer than supported")
                return nil
            }
            return try JSONDecoder().decode(ReviewsSnapshot.self, from: data)
        } catch {
            Self.logger.error("Failed to load reviews.json: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Replaces the file whole; a failure is logged, not thrown.
    func save(_ snapshot: ReviewsSnapshot) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(snapshot).write(to: fileURL, options: .atomic)
        } catch {
            Self.logger.error("Failed to save reviews.json: \(error.localizedDescription, privacy: .public)")
        }
    }
}
