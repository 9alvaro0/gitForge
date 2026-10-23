import Foundation
import os

/// What the user chose to follow in Reviews, beyond the repos gitForge finds by
/// itself: the patterns they accepted, the repos they added by hand, the ones
/// they hid and the pattern proposals they already answered (R3 Ruling 8).
///
/// Kept in `reviews-settings.json` by `ReviewsConfigStore`. None of the lists is
/// de-duplicated here: that is the follow logic's job.
// Codable, Equatable and Sendable are declared here, not in an extension: with
// the app's MainActor default isolation, Xcode 26 makes an extension's
// conformance main actor-isolated, and the Reviews model needs this off it.
nonisolated struct ReviewsConfig: Codable, Equatable, Sendable {
    /// The newest layout this build reads and the one it writes.
    static let currentVersion = 1

    /// Accepted patterns, in the order they were accepted.
    var patterns: [FollowPattern] = []
    /// Repos followed by hand, in the order they were added.
    var manual: [RemoteHost] = []
    /// Repos kept out of Reviews, whatever source finds them.
    var hidden: [RemoteHost] = []
    /// `FollowPattern.id`s of the proposals the user answered, "Follow" or "Not now".
    var answeredProposals: [String] = []
}

/// What following something by hand or by pattern did (R3 Ruling 6).
nonisolated enum FollowOutcome: Equatable, Sendable {
    /// Applied.
    case done
    /// Not applied: the inbox would follow `total` repos, over the limit.
    case overLimit(total: Int)
}

/// A pattern gitForge offers to follow, with what it would do (R3 Ruling 3).
nonisolated struct PatternProposal: Equatable, Sendable {
    let pattern: FollowPattern
    /// Repos the pattern adds to the ones already followed.
    let adds: Int
    /// Repos followed with it, counting the ones the limit would leave out.
    let total: Int
}

/// Reads and writes the `ReviewsConfig` as `reviews-settings.json`, next to
/// `accounts.json` in Application Support.
///
/// Unlike `ReviewsSnapshotStore`, this file is the user's choice, not a cache:
/// one it can't read, or that a newer build wrote, is moved aside as
/// `reviews-settings.corrupted.<stamp>.json` and the settings start empty. It is
/// never overwritten silently.
@MainActor
final class ReviewsConfigStore {
    private static let logger = Logger(subsystem: "com.warwarelabs.gitForge", category: "reviews")

    private let fileURL: URL

    private struct VersionProbe: Decodable { let version: Int }

    /// The file's layout: the version next to the `ReviewsConfig` fields.
    private nonisolated struct Stored: Codable {
        var version: Int
        var patterns: [FollowPattern]
        var manual: [RemoteHost]
        var hidden: [RemoteHost]
        var answeredProposals: [String]
    }

    init(directory: URL? = nil) {
        let dir = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!.appendingPathComponent("gitForge", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("reviews-settings.json")
    }

    /// The stored settings; empty when there is no file, and also when the file
    /// is unreadable or newer than this build, which is moved aside first.
    ///
    /// A pattern whose text no longer passes `FollowPattern`'s rules (a hand
    /// edit) is dropped and the rest loads. The decoder doesn't check them
    /// itself, and a pattern like `*/*` would follow a whole instance.
    func load() -> ReviewsConfig {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return ReviewsConfig() }
        do {
            let data = try Data(contentsOf: fileURL)
            // Read the version alone first: a newer build may have changed the shape.
            let version = try JSONDecoder().decode(VersionProbe.self, from: data).version
            guard version <= ReviewsConfig.currentVersion else {
                Self.logger.error("reviews-settings.json version \(version, privacy: .public) is newer than supported")
                quarantine()
                return ReviewsConfig()
            }
            let stored = try JSONDecoder().decode(Stored.self, from: data)
            return ReviewsConfig(
                patterns: stored.patterns.compactMap { FollowPattern(host: $0.host, text: $0.text) },
                manual: stored.manual,
                hidden: stored.hidden,
                answeredProposals: stored.answeredProposals)
        } catch {
            Self.logger.error("Failed to load reviews-settings.json: \(error.localizedDescription, privacy: .public)")
            quarantine()
            return ReviewsConfig()
        }
    }

    /// Replaces the file whole; a failure is logged, not thrown.
    func save(_ config: ReviewsConfig) {
        let stored = Stored(version: ReviewsConfig.currentVersion, patterns: config.patterns, manual: config.manual,
                            hidden: config.hidden, answeredProposals: config.answeredProposals)
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(stored).write(to: fileURL, options: .atomic)
        } catch {
            Self.logger.error("Failed to save reviews-settings.json: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Keeps an unreadable file as evidence instead of overwriting it.
    private func quarantine() {
        let stamp = ISO8601DateFormatter().string(from: .now).replacingOccurrences(of: ":", with: "-")
        let dest = fileURL.deletingPathExtension().appendingPathExtension("corrupted.\(stamp).json")
        try? FileManager.default.moveItem(at: fileURL, to: dest)
    }
}
