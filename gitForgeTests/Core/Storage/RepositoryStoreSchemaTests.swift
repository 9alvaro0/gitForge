import Foundation
import Testing
@testable import gitForge

/// Each test gets its own temp directory (passed via the injected
/// `RepositoryStore(directory:)` init), so parallel test processes don't
/// collide on the shared Application Support `recents.json`.
@Suite("RepositoryStore — schema & quarantine")
struct RepositoryStoreSchemaTests {

    private func makeTempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("gitForge-store-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writeRecents(_ data: Data, in dir: URL) throws {
        try data.write(to: dir.appendingPathComponent("recents.json"))
    }

    @Test("Reads a v1 envelope and populates repositories")
    func readsV1Envelope() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        // Repository encodes its url under the `path` key (custom CodingKeys),
        // not as a stringified file:// URL.
        let json = """
        { "version": 1, "repositories": [
          { "path": "/tmp/repo-a", "lastOpenedAt": "2026-05-13T10:00:00Z" }
        ] }
        """
        try writeRecents(json.data(using: .utf8)!, in: dir)

        let store = RepositoryStore(directory: dir)
        await store.load()
        let repos = await store.repositories
        #expect(repos.count == 1)
        #expect(repos.first?.url.path(percentEncoded: false) == "/tmp/repo-a")
    }

    @Test("Reads a legacy bare-array (no envelope) and survives upgrade")
    func readsLegacyBareArray() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let json = """
        [ { "path": "/tmp/repo-legacy", "lastOpenedAt": "2026-05-13T10:00:00Z" } ]
        """
        try writeRecents(json.data(using: .utf8)!, in: dir)

        let store = RepositoryStore(directory: dir)
        await store.load()
        let repos = await store.repositories
        #expect(repos.count == 1)
        #expect(repos.first?.url.path(percentEncoded: false) == "/tmp/repo-legacy")
    }

    @Test("Corrupt JSON quarantines the file and loads empty")
    func corruptJsonQuarantined() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try writeRecents("totally not json".data(using: .utf8)!, in: dir)

        let store = RepositoryStore(directory: dir)
        await store.load()
        let repos = await store.repositories
        #expect(repos.isEmpty)
        let entries = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        #expect(entries.contains { $0.lastPathComponent.hasPrefix("recents.corrupted.") })
        // Original recents.json moved aside so the next persist() can't
        // overwrite the diagnostic blob.
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("recents.json").path(percentEncoded: false)) == false)
    }

    @Test("Envelope with newer schema version quarantines rather than dropping data")
    func newerVersionQuarantined() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let json = """
        { "version": 99, "repositories": [
          { "path": "/tmp/repo-future", "lastOpenedAt": "2026-05-13T10:00:00Z" }
        ] }
        """
        try writeRecents(json.data(using: .utf8)!, in: dir)

        let store = RepositoryStore(directory: dir)
        await store.load()
        let repos = await store.repositories
        #expect(repos.isEmpty)
        let entries = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        #expect(entries.contains { $0.lastPathComponent.hasPrefix("recents.corrupted.") })
    }

    @Test("Persist writes a v1 envelope on disk")
    func persistWritesEnvelope() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = RepositoryStore(directory: dir)
        await store.load()
        _ = await store.touch(URL(fileURLWithPath: "/tmp/persist-target"))

        let data = try Data(contentsOf: dir.appendingPathComponent("recents.json"))
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(decoded?["version"] as? Int == 1)
        #expect(decoded?["repositories"] is [Any])
    }
}
