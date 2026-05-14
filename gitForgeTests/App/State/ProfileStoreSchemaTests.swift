import Foundation
import Testing
@testable import gitForge

/// Validates the schema-versioning + corruption-quarantine added to
/// ProfileStore. The store reads/writes UserDefaults under the standard
/// suite, so every test snapshots and restores the relevant key + sweeps
/// any quarantine keys created during the test.
@Suite("ProfileStore — schema & quarantine", .serialized)
@MainActor
struct ProfileStoreSchemaTests {

    private static let storageKey = ProfileStore.storageKey
    private static let corruptedKeyPrefix = ProfileStore.corruptedKeyPrefix

    private func withCleanKey(_ body: () throws -> Void) rethrows {
        let defaults = UserDefaults.standard
        let backup = defaults.data(forKey: Self.storageKey)
        defaults.removeObject(forKey: Self.storageKey)
        defer {
            defaults.removeObject(forKey: Self.storageKey)
            // Sweep quarantine keys created during the test so successive
            // runs aren't polluted.
            let allKeys = defaults.dictionaryRepresentation().keys
            for key in allKeys where key.hasPrefix(Self.corruptedKeyPrefix) {
                defaults.removeObject(forKey: key)
            }
            if let backup { defaults.set(backup, forKey: Self.storageKey) }
        }
        try body()
    }

    private func writeRaw(_ data: Data) {
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    private func quarantineKeysCount() -> Int {
        UserDefaults.standard.dictionaryRepresentation().keys
            .filter { $0.hasPrefix(Self.corruptedKeyPrefix) }
            .count
    }

    @Test("Reads a v1 envelope and populates profiles")
    func readsV1Envelope() throws {
        try withCleanKey {
            let json = """
            { "version": 1, "profiles": [
              { "id": "00000000-0000-0000-0000-000000000001", "name": "Personal",
                "userName": "Alvaro", "userEmail": "alvaro@example.com" }
            ] }
            """
            writeRaw(json.data(using: .utf8)!)
            let store = ProfileStore()
            #expect(store.profiles.count == 1)
            #expect(store.profiles.first?.userEmail == "alvaro@example.com")
        }
    }

    @Test("Reads a legacy bare-array (no envelope) and keeps the profiles")
    func readsLegacyBareArray() throws {
        try withCleanKey {
            let json = """
            [ { "id": "00000000-0000-0000-0000-000000000002", "name": "Legacy",
                "userName": "Old", "userEmail": "old@example.com" } ]
            """
            writeRaw(json.data(using: .utf8)!)
            let store = ProfileStore()
            #expect(store.profiles.count == 1)
            #expect(store.profiles.first?.userEmail == "old@example.com")
        }
    }

    @Test("Corrupt bytes quarantine the blob and load empty")
    func corruptBlobQuarantined() throws {
        try withCleanKey {
            writeRaw("not even close to json".data(using: .utf8)!)
            let store = ProfileStore()
            #expect(store.profiles.isEmpty)
            #expect(quarantineKeysCount() == 1)
            // Primary key removed so the next save() doesn't overwrite the
            // diagnostic blob silently.
            #expect(UserDefaults.standard.data(forKey: Self.storageKey) == nil)
        }
    }

    @Test("Envelope with newer schema version quarantines instead of dropping data")
    func newerVersionQuarantined() throws {
        try withCleanKey {
            let json = """
            { "version": 99, "profiles": [
              { "id": "00000000-0000-0000-0000-000000000003", "name": "Future",
                "userName": "X", "userEmail": "x@x" } ] }
            """
            writeRaw(json.data(using: .utf8)!)
            let store = ProfileStore()
            #expect(store.profiles.isEmpty)
            #expect(quarantineKeysCount() == 1)
        }
    }

    @Test("Persist writes a v1 envelope")
    func persistWritesEnvelope() throws {
        try withCleanKey {
            let store = ProfileStore()
            store.add(GitProfile(name: "X", userName: "X", userEmail: "x@x"))
            let data = UserDefaults.standard.data(forKey: Self.storageKey)
            #expect(data != nil)
            let decoded = try JSONSerialization.jsonObject(with: data!) as? [String: Any]
            #expect(decoded?["version"] as? Int == 1)
            #expect(decoded?["profiles"] is [Any])
        }
    }
}
