import Foundation
import Testing
@testable import gitForge

@Suite("TextFile")
struct TextFileTests {

    @Test("UTF-8 and Latin-1 files round-trip byte for byte")
    func roundTrip() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gitForge-text-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        for (name, bytes) in [("utf8.txt", Data("café\n".utf8)),
                              ("latin1.txt", Data("caf".utf8) + Data([0xE9, 0x0A]))] {
            let url = dir.appendingPathComponent(name)
            try bytes.write(to: url)
            let contents = try TextFile.read(url)
            try TextFile.write(contents.text, encoding: contents.encoding, to: url)
            #expect(try Data(contentsOf: url) == bytes, "\(name)")
        }
    }
}

/// The resolver used to read and write conflicted files as strict UTF-8: a
/// Latin-1 file couldn't be opened, and rewriting it would have mangled its
/// non-ASCII bytes.
@Suite("ConflictStore — encodings", .serialized)
@MainActor
struct ConflictStoreEncodingTests {

    /// ASCII text with every `*` turned into a Latin-1 `é` (0xE9) — an
    /// invalid UTF-8 byte on its own.
    private nonisolated static func latin1(_ text: String) -> [UInt8] {
        Data(text.utf8).map { $0 == 0x2A ? 0xE9 : $0 }
    }

    @Test("A Latin-1 conflict is listed, parsed and resolved without touching other bytes")
    func latin1Conflict() async throws {
        let repo = try await GitTestRepo.make { repo in
            try repo.write(Data(Self.latin1("caf* base\nshared\n")), to: "menu.txt")
            try repo.git("add", "-A"); try repo.git("commit", "-qm", "base")
            try repo.git("checkout", "-q", "-b", "other")
            try repo.write(Data(Self.latin1("caf* theirs\nshared\n")), to: "menu.txt")
            try repo.git("commit", "-qam", "theirs")
            try repo.git("checkout", "-q", "main")
            try repo.write(Data(Self.latin1("caf* ours\nshared\n")), to: "menu.txt")
            try repo.git("commit", "-qam", "ours")
            try repo.git(["merge", "other"], allowFailure: true)
        }
        defer { repo.remove() }

        let store = ConflictStore(repositoryURL: repo.url)
        await store.reload(unmergedPaths: ["menu.txt"])
        #expect(store.files.first?.conflicts == 1)
        let hunk = try #require(store.hunks.first)

        store.setPick(hunkId: hunk.id, pick: .theirs)
        #expect(try await store.writeResolution() == "menu.txt")
        let written = try Data(contentsOf: repo.url.appendingPathComponent("menu.txt"))
        #expect(written == Data(Self.latin1("caf* theirs\nshared\n")))
    }

    @Test("Resolving while another mutation runs is refused")
    func resolveRespectsIsMutating() async throws {
        let vm = RepositoryViewModel(repository: Repository(url: URL(fileURLWithPath: "/var/empty")))
        vm.isMutating = true
        await vm.resolveFile(at: "x.txt", using: .ours)
        #expect(vm.commitError == "Another operation is in progress.")
    }
}
