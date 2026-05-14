import Foundation
import os

actor RepositoryStore {
    private static let logger = Logger(subsystem: "com.warwarelabs.gitForge", category: "store")
    /// Current persisted-format version. Bump when a non-backward-compatible
    /// field is added (existing fields can be made optional without a bump).
    /// On mismatch the existing blob is quarantined rather than silently
    /// overwritten — see `quarantineCorruptedFile`.
    private static let schemaVersion = 1

    private let fileURL: URL
    private(set) var repositories: [Repository] = []

    /// Persisted envelope. Wrapping the array lets us bump the schema and
    /// keep room for future top-level metadata (last-opened section per
    /// repo, sort order, etc.) without another migration pass.
    private struct StoredRecents: Codable {
        let version: Int
        let repositories: [Repository]
    }

    /// Production path uses Application Support; tests inject a temp dir so
    /// parallel test runs (Swift Testing fans tests across processes) don't
    /// stomp the shared recents.json.
    init(directory: URL? = nil) {
        let dir: URL
        if let directory {
            dir = directory
        } else {
            let support = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first ?? FileManager.default.temporaryDirectory
            dir = support.appendingPathComponent("gitForge", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("recents.json")
    }

    func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) else {
            repositories = []
            return
        }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            // v1 envelope first; fall back to the bare-array legacy format
            // so users upgrading from a pre-versioned build don't lose recents.
            if let stored = try? decoder.decode(StoredRecents.self, from: data) {
                if stored.version > Self.schemaVersion {
                    Self.logger.error("recents.json schema \(stored.version, privacy: .public) is newer than supported \(Self.schemaVersion, privacy: .public); quarantining")
                    quarantineCorruptedFile()
                    repositories = []
                    return
                }
                repositories = stored.repositories
                sort()
                // Re-persist to write the envelope on next mutation; no-op
                // beyond that until something changes.
                return
            }
            repositories = try decoder.decode([Repository].self, from: data)
            sort()
        } catch {
            Self.logger.error("Failed to load recents.json: \(error.localizedDescription, privacy: .public)")
            quarantineCorruptedFile()
            repositories = []
        }
    }

    /// Renames a corrupt/unreadable `recents.json` to
    /// `recents.corrupted.<timestamp>.json` so the next persist() doesn't
    /// silently overwrite the diagnostic evidence. Best-effort — failure to
    /// move just leaves the original blob; the next save will overwrite it.
    private func quarantineCorruptedFile() {
        let stamp = ISO8601DateFormatter().string(from: .now)
            .replacingOccurrences(of: ":", with: "-")
        let dest = fileURL.deletingPathExtension()
            .appendingPathExtension("corrupted.\(stamp).json")
        do {
            try FileManager.default.moveItem(at: fileURL, to: dest)
            Self.logger.error("Quarantined corrupt recents to \(dest.lastPathComponent, privacy: .public)")
        } catch {
            Self.logger.error("Quarantine failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    @discardableResult
    func touch(_ url: URL) -> [Repository] {
        if let index = repositories.firstIndex(where: { $0.url == url }) {
            // Bookkeeping only — no reordering. The user found the
            // "recently-used floats to top" behavior disorienting.
            repositories[index].lastOpenedAt = .now
        } else {
            repositories.append(Repository(url: url))
            sort()
        }
        persist()
        return repositories
    }

    @discardableResult
    func remove(_ url: URL) -> [Repository] {
        repositories.removeAll { $0.url == url }
        persist()
        return repositories
    }

    /// Stable alphabetical order by repo name. Predictable across launches
    /// and immune to whatever the user just clicked.
    private func sort() {
        repositories.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let envelope = StoredRecents(version: Self.schemaVersion, repositories: repositories)
            let data = try encoder.encode(envelope)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            Self.logger.error("Failed to persist recents.json: \(error.localizedDescription, privacy: .public)")
        }
    }
}
