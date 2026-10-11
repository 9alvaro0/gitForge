import Foundation
import Testing
@testable import gitForge

/// The old per-host store, in memory, recording deletes.
private final class RemovableLegacy: LegacyTokenStore, @unchecked Sendable {
    struct Failed: Error {}
    private let lock = NSLock()
    private var tokens: [String: String]
    private var failRead: Set<String> = []
    private var failRemove: Set<String> = []
    private var log: [String] = []

    init(_ tokens: [String: String]) { self.tokens = tokens }

    func failing(read: Set<String> = [], remove: Set<String> = []) {
        lock.withLock { failRead = read; failRemove = remove }
    }

    var remaining: [String] { lock.withLock { tokens.keys.sorted() } }
    var removed: [String] { lock.withLock { log.sorted() } }

    func legacyHosts() throws -> [String] { lock.withLock { tokens.keys.sorted() } }

    func legacyToken(for host: String) throws -> String? {
        try lock.withLock {
            if failRead.contains(host) { throw Failed() }
            return tokens[host]
        }
    }

    func removeLegacyToken(for host: String) throws {
        try lock.withLock {
            if failRemove.contains(host) { throw Failed() }
            tokens[host] = nil
            log.append(host)
        }
    }
}

@Suite("Accounts — retiring the old host tokens", .serialized)
@MainActor
struct AccountLegacyRetirementTests {

    private static func store(_ secrets: InMemoryAccountSecretStore = .init()) -> AccountStore {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gitForge-retire-\(UUID().uuidString)")
        return AccountStore(directory: dir, secrets: secrets)
    }

    @Test("After a complete sync the copied hosts' old entries are deleted; the accounts keep their tokens")
    func retires() {
        let secrets = InMemoryAccountSecretStore()
        let store = Self.store(secrets)
        let legacy = RemovableLegacy(["github.com": "test-gh", "gitlab.example.org": "test-gl"])
        store.retireLegacyTokens(from: legacy)
        #expect(legacy.remaining.isEmpty)
        #expect(legacy.removed == ["github.com", "gitlab.example.org"])
        #expect(store.accounts.count == 2)
        #expect(Set(store.accounts.compactMap { store.secret(for: $0.id)?.accessToken }) == ["test-gh", "test-gl"])
        #expect(store.migratedLegacyTokens)
    }

    @Test("An incomplete sync deletes nothing")
    func incomplete() {
        let store = Self.store()
        let legacy = RemovableLegacy(["github.com": "test-gh", "gitlab.example.org": "test-gl"])
        legacy.failing(read: ["gitlab.example.org"])
        store.retireLegacyTokens(from: legacy)
        #expect(legacy.removed.isEmpty)
        #expect(!store.migratedLegacyTokens)
    }

    @Test("A sync that fails now deletes nothing, even after an earlier complete one")
    func failsNow() {
        let store = Self.store()
        let legacy = RemovableLegacy(["github.com": "test-gh", "gitlab.example.org": "test-gl"])
        #expect(store.migrateLegacyTokens(from: legacy))
        legacy.failing(read: ["github.com"])
        store.retireLegacyTokens(from: legacy)
        #expect(legacy.removed.isEmpty)
        #expect(legacy.remaining == ["github.com", "gitlab.example.org"])
    }

    @Test("Hosts the sync can't type stay; a disconnected copy's host goes")
    func untypedAndDetached() throws {
        let store = Self.store()
        let legacy = RemovableLegacy(["github.com": "test-gh", "git.unknown.test": "test-x"])
        store.migrateLegacyTokens(from: legacy)
        let copy = try #require(store.legacyHostAccounts["github.com"])
        store.removeAccount(copy)
        store.retireLegacyTokens(from: legacy)
        #expect(legacy.removed == ["github.com"])
        #expect(legacy.remaining == ["git.unknown.test"])
        #expect(store.accounts.isEmpty)
    }

    @Test("A failed delete is left for the next launch")
    func retriesDelete() {
        let store = Self.store()
        let legacy = RemovableLegacy(["github.com": "test-gh"])
        legacy.failing(remove: ["github.com"])
        store.retireLegacyTokens(from: legacy)
        #expect(legacy.remaining == ["github.com"])
        legacy.failing()
        store.retireLegacyTokens(from: legacy)
        #expect(legacy.remaining.isEmpty)
        #expect(store.accounts.count == 1)
    }
}
