import Foundation

/// Author avatars kept on disk between launches (#65), one small JSON file
/// per author and host: the avatar's URL, the picture itself, and when it
/// was read. An entry past its expiry reads as missing, so the host is asked
/// again; "this author has no avatar" is kept too, for less time.
///
/// Files are named by a hash of the key and carry the key itself, so a hash
/// collision reads as a miss rather than someone else's picture.
nonisolated struct AvatarDiskCache: Sendable {
    struct Entry: Codable, Equatable, Sendable {
        /// "<host>\n<normalized email>".
        let key: String
        /// `nil`: the host has no avatar of its own for this author.
        let avatarURL: URL?
        let image: Data?
        let fetchedAt: Date
    }

    let directory: URL
    /// A found avatar is used this long before the host is asked again.
    var foundLifetime: TimeInterval = 7 * 24 * 3600
    /// "No avatar" is trusted this long: the author may set one up.
    var missingLifetime: TimeInterval = 24 * 3600
    let now: @Sendable () -> Date

    init(directory: URL = Self.defaultDirectory, now: @escaping @Sendable () -> Date = { Date() }) {
        self.directory = directory
        self.now = now
    }

    /// `~/Library/Caches/gitForge/Avatars`: the system may clear it, and
    /// that only costs a new read.
    static var defaultDirectory: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return caches.appendingPathComponent("gitForge/Avatars", isDirectory: true)
    }

    static func key(host: String, email: String) -> String {
        "\(host.lowercased())\n\(email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
    }

    /// The entry for `key` while it's fresh; `nil` when missing, expired,
    /// unreadable or someone else's (a hash collision).
    func entry(for key: String) -> Entry? {
        guard let data = try? Data(contentsOf: fileURL(for: key)),
              let entry = try? JSONDecoder().decode(Entry.self, from: data),
              entry.key == key,
              isFresh(entry) else { return nil }
        return entry
    }

    /// Writes atomically; a failure (disk full, no folder) only loses the cache.
    func store(_ entry: Entry) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(entry)
            try data.write(to: fileURL(for: entry.key), options: .atomic)
        } catch {
            // Best effort: the next launch asks the host again.
        }
    }

    func isFresh(_ entry: Entry) -> Bool {
        let lifetime = entry.avatarURL != nil && entry.image != nil ? foundLifetime : missingLifetime
        let age = now().timeIntervalSince(entry.fetchedAt)
        return age >= 0 && age < lifetime
    }

    /// Deletes the files nobody would read any more (older than the longest
    /// lifetime), so the folder doesn't grow with every author ever seen.
    func prune() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey]) else {
            return
        }
        let limit = now().addingTimeInterval(-max(foundLifetime, missingLifetime))
        for file in files where file.pathExtension == "json" {
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let modified, modified < limit { try? fm.removeItem(at: file) }
        }
    }

    func fileURL(for key: String) -> URL {
        directory.appendingPathComponent(Self.fileName(for: key))
    }

    /// FNV-1a, 64 bit, in hex: stable across launches and platforms.
    static func fileName(for key: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in key.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        let hex = String(hash, radix: 16)
        return String(repeating: "0", count: 16 - hex.count) + hex + ".json"
    }
}
