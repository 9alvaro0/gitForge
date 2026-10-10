import Foundation
import Testing
@testable import gitForge

@Suite("Conflict resolver — editing the result by hand", .serialized)
@MainActor
struct ConflictManualEditTests {

    private static let conflicted = "a\n<<<<<<< HEAD\nours\n=======\ntheirs\n>>>>>>> b\nz\n"

    private static func makeStore() throws -> (ConflictStore, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gitForge-manual-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try conflicted.write(to: dir.appendingPathComponent("f.txt"), atomically: true, encoding: .utf8)
        return (ConflictStore(repositoryURL: dir), dir)
    }

    @Test("Editing starts from the picks, keeping markers for unpicked hunks, and blocks Mark resolved until they're gone")
    func startsFromPicks() async throws {
        let (store, dir) = try Self.makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        await store.loadHunks(for: "f.txt")
        store.beginManualEdit()
        #expect(store.manualText == Self.conflicted)
        #expect(store.manualTextHasMarkers)
        #expect(!store.canMarkResolved)

        store.manualText = "a\nmine\nz\n"
        #expect(store.canMarkResolved)
    }

    @Test("Mark resolved writes the hand-written text as is")
    func writesManualText() async throws {
        let (store, dir) = try Self.makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        await store.loadHunks(for: "f.txt")
        store.beginManualEdit()
        store.manualText = "a\nmine\nz\n"
        _ = try await store.writeResolution()
        #expect(try String(contentsOf: dir.appendingPathComponent("f.txt"), encoding: .utf8) == "a\nmine\nz\n")
    }

    @Test("A file changed on disk since loading is not overwritten")
    func refusesChangedFile() async throws {
        let (store, dir) = try Self.makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        await store.loadHunks(for: "f.txt")
        store.beginManualEdit()
        store.manualText = "a\nmine\nz\n"
        let edited = Self.conflicted + "added elsewhere\n"
        try edited.write(to: dir.appendingPathComponent("f.txt"), atomically: true, encoding: .utf8)
        await #expect(throws: ConflictStore.ResolveError.self) { try await store.writeResolution() }
        #expect(try String(contentsOf: dir.appendingPathComponent("f.txt"), encoding: .utf8) == edited)
    }

    @Test("Discarding the edits, or loading another file, goes back to the picks")
    func discard() async throws {
        let (store, dir) = try Self.makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        await store.loadHunks(for: "f.txt")
        store.beginManualEdit()
        store.discardManualEdit()
        #expect(store.manualText == nil)
        store.beginManualEdit()
        await store.loadHunks(for: "f.txt")
        #expect(store.manualText == nil)
    }
}
