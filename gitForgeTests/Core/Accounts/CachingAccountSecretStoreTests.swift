import Foundation
import Testing
@testable import gitForge

@Suite("Account secrets kept in memory")
struct CachingAccountSecretStoreTests {
    let id = UUID()
    let first = AccountSecret(accessToken: "access-1", refreshToken: "refresh-1")
    let second = AccountSecret(accessToken: "access-2", refreshToken: "refresh-2")

    @Test("A secret is read from the Keychain once; later reads come from memory")
    func readsOnce() throws {
        let keychain = CountingSecretStore()
        try keychain.backing.write(first, for: id)
        let store = CachingAccountSecretStore(keychain)
        #expect(store.read(id) == first)
        #expect(store.read(id) == first)
        #expect(store.read(id) == first)
        #expect(keychain.reads == 1)
    }

    @Test("Concurrent first reads of one account make a single Keychain read")
    func concurrentFirstReads() throws {
        let keychain = CountingSecretStore(readDelay: 0.05)
        try keychain.backing.write(first, for: id)
        let store = CachingAccountSecretStore(keychain)
        let results = LockedList<AccountSecret?>()
        let id = self.id
        DispatchQueue.concurrentPerform(iterations: 8) { _ in
            results.append(store.read(id))
        }
        #expect(results.values == Array(repeating: first, count: 8))
        #expect(keychain.reads == 1)
    }

    @Test("Each account is read once, on its own")
    func accountsApart() throws {
        let keychain = CountingSecretStore()
        let other = UUID()
        try keychain.backing.write(first, for: id)
        try keychain.backing.write(second, for: other)
        let store = CachingAccountSecretStore(keychain)
        #expect(store.read(id) == first)
        #expect(store.read(other) == second)
        #expect(store.read(id) == first)
        #expect(store.read(other) == second)
        #expect(keychain.reads == 2)
    }

    @Test("A write reaches the Keychain and later reads don't go back to it")
    func writeThrough() throws {
        let keychain = CountingSecretStore()
        let store = CachingAccountSecretStore(keychain)
        try store.write(first, for: id)
        #expect(keychain.backing.read(id) == first)
        #expect(store.read(id) == first)
        #expect(keychain.reads == 0)
    }

    @Test("A write the Keychain refuses leaves the previous secret")
    func failedWrite() throws {
        let keychain = CountingSecretStore()
        try keychain.backing.write(first, for: id)
        let store = CachingAccountSecretStore(keychain)
        #expect(store.read(id) == first)
        keychain.backing.failWrites = true
        #expect(throws: (any Error).self) { try store.write(second, for: id) }
        #expect(store.read(id) == first)
        #expect(keychain.backing.read(id) == first)
    }

    @Test("Delete removes the secret from both; the next read asks the Keychain")
    func deleteBoth() throws {
        let keychain = CountingSecretStore()
        try keychain.backing.write(first, for: id)
        let store = CachingAccountSecretStore(keychain)
        #expect(store.read(id) == first)
        store.delete(id)
        #expect(keychain.backing.read(id) == nil)
        #expect(store.read(id) == nil)
        #expect(keychain.reads == 2)
    }

    @Test("A missing secret isn't remembered: the next read asks the Keychain again")
    func missNotKept() throws {
        let keychain = CountingSecretStore()
        let store = CachingAccountSecretStore(keychain)
        #expect(store.read(id) == nil)
        try keychain.backing.write(first, for: id)
        #expect(store.read(id) == first)
        #expect(keychain.reads == 2)
    }

    @Test("Forget: the next read goes to the Keychain and sees what another copy of the app wrote")
    func forgetRereads() throws {
        let keychain = CountingSecretStore()
        try keychain.backing.write(first, for: id)
        let store = CachingAccountSecretStore(keychain)
        #expect(store.read(id) == first)
        // Another copy of the app rotates the secret behind this one's back.
        try keychain.backing.write(second, for: id)
        #expect(store.read(id) == first)
        store.forget(id)
        #expect(store.read(id) == second)
        #expect(keychain.reads == 2)
    }
}

/// A Keychain stand-in that counts reads and can hold each one, like a read
/// waiting on a password prompt.
private final class CountingSecretStore: AccountSecretStore, @unchecked Sendable {
    let backing = InMemoryAccountSecretStore()
    private let readDelay: TimeInterval
    private let lock = NSLock()
    private var count = 0

    init(readDelay: TimeInterval = 0) {
        self.readDelay = readDelay
    }

    var reads: Int { lock.withLock { count } }

    func read(_ id: UUID) -> AccountSecret? {
        lock.withLock { count += 1 }
        if readDelay > 0 { Thread.sleep(forTimeInterval: readDelay) }
        return backing.read(id)
    }

    func write(_ secret: AccountSecret, for id: UUID) throws {
        try backing.write(secret, for: id)
    }

    func delete(_ id: UUID) {
        backing.delete(id)
    }

    func forget(_ id: UUID) {}
}
