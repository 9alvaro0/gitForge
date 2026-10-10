import Foundation
import Testing
@testable import gitForge

/// Validates the schema-versioning + corruption-quarantine added to
/// ProfileStore. Every test runs against its own throwaway `UserDefaults`
/// suite (the store is injectable), so nothing touches the user's real
/// profiles or quarantine keys.
@Suite("ProfileStore — schema & quarantine", .serialized)
@MainActor
struct ProfileStoreSchemaTests {

    private static let storageKey = ProfileStore.storageKey
    private static let corruptedKeyPrefix = ProfileStore.corruptedKeyPrefix

    private func withCleanKey(_ body: (UserDefaults) throws -> Void) rethrows {
        try TestDefaults.with(prefix: "gitForge-profiles-tests") { try body($0.defaults) }
    }

    private func writeRaw(_ defaults: UserDefaults, _ data: Data) {
        defaults.set(data, forKey: Self.storageKey)
    }

    private func quarantineKeysCount(_ defaults: UserDefaults) -> Int {
        defaults.dictionaryRepresentation().keys
            .filter { $0.hasPrefix(Self.corruptedKeyPrefix) }
            .count
    }

    @Test("Reads a v1 envelope and populates profiles")
    func readsV1Envelope() {
        withCleanKey { defaults in
            let json = """
            { "version": 1, "profiles": [
              { "id": "00000000-0000-0000-0000-000000000001", "name": "Personal",
                "userName": "Alvaro", "userEmail": "alvaro@example.com" }
            ] }
            """
            writeRaw(defaults, json.data(using: .utf8)!)
            let store = ProfileStore(defaults: defaults)
            #expect(store.profiles.count == 1)
            #expect(store.profiles.first?.userEmail == "alvaro@example.com")
        }
    }

    @Test("Reads a legacy bare-array (no envelope) and keeps the profiles")
    func readsLegacyBareArray() {
        withCleanKey { defaults in
            let json = """
            [ { "id": "00000000-0000-0000-0000-000000000002", "name": "Legacy",
                "userName": "Old", "userEmail": "old@example.com" } ]
            """
            writeRaw(defaults, json.data(using: .utf8)!)
            let store = ProfileStore(defaults: defaults)
            #expect(store.profiles.count == 1)
            #expect(store.profiles.first?.userEmail == "old@example.com")
        }
    }

    @Test("Corrupt bytes quarantine the blob and load empty")
    func corruptBlobQuarantined() {
        withCleanKey { defaults in
            writeRaw(defaults, "not even close to json".data(using: .utf8)!)
            let store = ProfileStore(defaults: defaults)
            #expect(store.profiles.isEmpty)
            #expect(quarantineKeysCount(defaults) == 1)
            // Primary key removed so the next save() doesn't overwrite the
            // diagnostic blob silently.
            #expect(defaults.data(forKey: Self.storageKey) == nil)
        }
    }

    @Test("Envelope with newer schema version quarantines instead of dropping data")
    func newerVersionQuarantined() {
        withCleanKey { defaults in
            let json = """
            { "version": 99, "profiles": [
              { "id": "00000000-0000-0000-0000-000000000003", "name": "Future",
                "userName": "X", "userEmail": "x@x" } ] }
            """
            writeRaw(defaults, json.data(using: .utf8)!)
            let store = ProfileStore(defaults: defaults)
            #expect(store.profiles.isEmpty)
            #expect(quarantineKeysCount(defaults) == 1)
        }
    }

    @Test("Persist writes a v1 envelope")
    func persistWritesEnvelope() throws {
        try withCleanKey { defaults in
            let store = ProfileStore(defaults: defaults)
            store.add(GitProfile(name: "X", userName: "X", userEmail: "x@x"))
            let data = defaults.data(forKey: Self.storageKey)
            #expect(data != nil)
            let decoded = try JSONSerialization.jsonObject(with: data!) as? [String: Any]
            #expect(decoded?["version"] as? Int == 1)
            #expect(decoded?["profiles"] is [Any])
        }
    }
}
