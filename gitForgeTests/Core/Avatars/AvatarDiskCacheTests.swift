import Foundation
import Testing
@testable import gitForge

@Suite("AvatarDiskCache")
struct AvatarDiskCacheTests {
    /// A clock the test moves.
    final class Clock: @unchecked Sendable {
        private let lock = NSLock()
        private var value = Date(timeIntervalSince1970: 1_800_000_000)
        var now: Date { lock.withLock { value } }
        func advance(_ seconds: TimeInterval) { lock.withLock { value = value.addingTimeInterval(seconds) } }
    }

    private func makeCache(_ clock: Clock) -> AvatarDiskCache {
        AvatarDiskCache(directory: TemporaryDirectories.make("gitForge-avatars"), now: { clock.now })
    }

    private let key = AvatarDiskCache.key(host: "GitHub.com", email: " Ana@Forge.dev ")

    @Test("The key is the host and the email, case and spacing aside")
    func keyNormalization() {
        #expect(key == "github.com\nana@forge.dev")
    }

    @Test("A found avatar is read back with its picture until it expires (7 days)")
    func foundRoundTrip() {
        let clock = Clock()
        let cache = makeCache(clock)
        let entry = AvatarDiskCache.Entry(key: key, avatarURL: URL(string: "https://avatars.githubusercontent.com/u/1?s=64"),
                                          image: Data([1, 2, 3]), fetchedAt: clock.now)
        cache.store(entry)
        #expect(cache.entry(for: key) == entry)
        clock.advance(6 * 24 * 3600)
        #expect(cache.entry(for: key) == entry)
        clock.advance(2 * 24 * 3600)
        #expect(cache.entry(for: key) == nil)
    }

    @Test("\"No avatar\" is kept for a day only")
    func missingExpiresSooner() {
        let clock = Clock()
        let cache = makeCache(clock)
        cache.store(AvatarDiskCache.Entry(key: key, avatarURL: nil, image: nil, fetchedAt: clock.now))
        #expect(cache.entry(for: key)?.avatarURL == nil)
        #expect(cache.entry(for: key) != nil)
        clock.advance(25 * 3600)
        #expect(cache.entry(for: key) == nil)
    }

    @Test("An entry from the future (clock moved back) reads as expired")
    func futureEntry() {
        let clock = Clock()
        let cache = makeCache(clock)
        cache.store(AvatarDiskCache.Entry(key: key, avatarURL: nil, image: nil, fetchedAt: clock.now.addingTimeInterval(3600)))
        #expect(cache.entry(for: key) == nil)
    }

    @Test("A file holding another key (a hash collision) is a miss, not someone else's picture")
    func collision() throws {
        let clock = Clock()
        let cache = makeCache(clock)
        let other = AvatarDiskCache.Entry(key: "github.com\nsomeone@else.dev", avatarURL: URL(string: "https://github.com/x.png"),
                                          image: Data([9]), fetchedAt: clock.now)
        try FileManager.default.createDirectory(at: cache.directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(other).write(to: cache.fileURL(for: key))
        #expect(cache.entry(for: key) == nil)
    }

    @Test("Unreadable files and a missing folder are misses")
    func unreadable() throws {
        let cache = makeCache(Clock())
        #expect(cache.entry(for: key) == nil)
        try FileManager.default.createDirectory(at: cache.directory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: cache.fileURL(for: key))
        #expect(cache.entry(for: key) == nil)
    }

    @Test("File names are a stable 64-bit FNV-1a hash")
    func fileNames() {
        #expect(AvatarDiskCache.fileName(for: "") == "cbf29ce484222325.json")
        #expect(AvatarDiskCache.fileName(for: "a") == "af63dc4c8601ec8c.json")
        #expect(AvatarDiskCache.fileName(for: key) == AvatarDiskCache.fileName(for: key))
        #expect(AvatarDiskCache.fileName(for: key) != AvatarDiskCache.fileName(for: key + "x"))
    }

    @Test("Pruning deletes files older than the longest lifetime and keeps the rest")
    func prune() throws {
        let clock = Clock()
        let cache = makeCache(clock)
        let fresh = AvatarDiskCache.key(host: "github.com", email: "fresh@forge.dev")
        cache.store(AvatarDiskCache.Entry(key: key, avatarURL: nil, image: nil, fetchedAt: clock.now))
        cache.store(AvatarDiskCache.Entry(key: fresh, avatarURL: nil, image: nil, fetchedAt: clock.now))
        try FileManager.default.setAttributes([.modificationDate: clock.now.addingTimeInterval(-8 * 24 * 3600)],
                                              ofItemAtPath: cache.fileURL(for: key).path)
        try FileManager.default.setAttributes([.modificationDate: clock.now.addingTimeInterval(-3600)],
                                              ofItemAtPath: cache.fileURL(for: fresh).path)
        cache.prune()
        #expect(!FileManager.default.fileExists(atPath: cache.fileURL(for: key).path))
        #expect(FileManager.default.fileExists(atPath: cache.fileURL(for: fresh).path))
    }
}
