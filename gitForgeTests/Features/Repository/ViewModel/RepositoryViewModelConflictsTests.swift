import Foundation
import Testing
@testable import gitForge

@Suite("ConflictParser — parse")
struct ConflictParserParseTests {

    @Test("Parses a 2-way conflict (ours / theirs)")
    func parses2way() {
        let content = """
        line1
        <<<<<<< HEAD
        ours-a
        ours-b
        =======
        theirs-a
        >>>>>>> branch
        line2
        """
        let result = ConflictParser.parse(content)
        #expect(result.hunks.count == 1)
        #expect(result.hunks[0].ours == ["ours-a", "ours-b"])
        #expect(result.hunks[0].base.isEmpty)
        #expect(result.hunks[0].theirs == ["theirs-a"])
    }

    @Test("Parses a 3-way diff3-style conflict (ours / base / theirs)")
    func parses3way() {
        let content = """
        <<<<<<< HEAD
        ours
        ||||||| common
        base-line
        =======
        theirs
        >>>>>>> branch
        """
        let result = ConflictParser.parse(content)
        #expect(result.hunks.count == 1)
        #expect(result.hunks[0].ours == ["ours"])
        #expect(result.hunks[0].base == ["base-line"])
        #expect(result.hunks[0].theirs == ["theirs"])
    }

    @Test("Returns no hunks for a file without markers")
    func noMarkers() {
        let result = ConflictParser.parse("just plain content\nnothing here")
        #expect(result.hunks.isEmpty)
    }

    @Test("Handles multiple hunks in one file")
    func multipleHunks() {
        let content = """
        <<<<<<< HEAD
        a
        =======
        b
        >>>>>>> branch
        between
        <<<<<<< HEAD
        c
        =======
        d
        >>>>>>> branch
        """
        let result = ConflictParser.parse(content)
        #expect(result.hunks.count == 2)
    }
}

@Suite("ConflictParser — apply")
struct ConflictParserApplyTests {

    private func sampleContent() -> String {
        """
        before
        <<<<<<< HEAD
        ours
        =======
        theirs
        >>>>>>> branch
        after
        """
    }

    @Test("With no picks, returns content unchanged")
    func noPicksLeavesContentAlone() {
        let content = sampleContent()
        let parsed = ConflictParser.parse(content)
        let result = ConflictParser.apply(content: content, picks: [:], hunks: parsed.hunks)
        #expect(result == content)
    }

    @Test(".ours pick replaces the conflict block with the ours side")
    func picksOurs() {
        let content = sampleContent()
        let parsed = ConflictParser.parse(content)
        let result = ConflictParser.apply(content: content,
                                          picks: [parsed.hunks[0].id: .ours],
                                          hunks: parsed.hunks)
        #expect(result.contains("ours"))
        #expect(!result.contains("theirs"))
        #expect(!result.contains("<<<<<<<"))
        #expect(!result.contains("======="))
        #expect(!result.contains(">>>>>>>"))
    }

    @Test(".theirs pick replaces the conflict block with the theirs side")
    func picksTheirs() {
        let content = sampleContent()
        let parsed = ConflictParser.parse(content)
        let result = ConflictParser.apply(content: content,
                                          picks: [parsed.hunks[0].id: .theirs],
                                          hunks: parsed.hunks)
        #expect(result.contains("theirs"))
        #expect(!result.contains("<<<<<<<"))
    }

    @Test(".both concatenates ours then theirs")
    func picksBoth() {
        let content = sampleContent()
        let parsed = ConflictParser.parse(content)
        let result = ConflictParser.apply(content: content,
                                          picks: [parsed.hunks[0].id: .both],
                                          hunks: parsed.hunks)
        let oursIdx = result.range(of: "ours")?.lowerBound
        let theirsIdx = result.range(of: "theirs")?.lowerBound
        #expect(oursIdx != nil && theirsIdx != nil)
        if let o = oursIdx, let t = theirsIdx { #expect(o < t) }
    }

    @Test("Hunks count mismatch returns content unchanged")
    func mismatchedHunksLeavesContentAlone() {
        // Caller's hunks array is out of sync with on-disk content (e.g.
        // external edit between read and write); apply must not silently
        // produce a half-resolved file.
        let content = sampleContent()
        let staleHunk = ConflictHunk(ours: ["x"], base: [], theirs: ["y"])
        let result = ConflictParser.apply(content: content,
                                          picks: [staleHunk.id: .ours],
                                          hunks: [staleHunk, staleHunk])  // count differs from 1
        #expect(result == content)
    }
}

@Suite("RepositoryViewModel — conflict load token", .serialized)
@MainActor
struct RepositoryViewModelConflictTokenTests {

    private static func makeVM() -> RepositoryViewModel {
        let url = URL(fileURLWithPath: "/var/empty/gitForge-tests-\(UUID().uuidString)")
        return RepositoryViewModel(repository: Repository(url: url))
    }

    @Test("loadConflictHunks bumps the gen token even on missing files")
    func bumpsGenOnMissingFile() async {
        let vm = Self.makeVM()
        let before = vm.conflictHunksGen
        await vm.loadConflictHunks(for: "definitely-not-here.swift")
        #expect(vm.conflictHunksGen > before)
        #expect(vm.selectedConflictPath == "definitely-not-here.swift")
        #expect(vm.conflictHunks.isEmpty)
        #expect(vm.conflictPicks.isEmpty)
    }

    @Test("loadConflictHunks for a real file populates hunks and resets picks")
    func populatesHunksFromRealFile() async throws {
        // Write a small conflicted file into the VM's repo URL so the loader
        // hits a real disk path. We're not exercising git here — only the
        // file-read + parse path.
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("gitForge-conflict-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let conflictPath = "Sources/foo.swift"
        let absolute = tmp.appendingPathComponent(conflictPath)
        try FileManager.default.createDirectory(
            at: absolute.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let content = """
        keep
        <<<<<<< HEAD
        ours
        =======
        theirs
        >>>>>>> branch
        keep
        """
        try content.write(to: absolute, atomically: true, encoding: .utf8)

        let vm = RepositoryViewModel(repository: Repository(url: tmp))
        // Pre-populate picks so we can verify they're cleared on load.
        vm.conflictPicks = [UUID(): .ours]

        await vm.loadConflictHunks(for: conflictPath)

        #expect(vm.selectedConflictPath == conflictPath)
        #expect(vm.conflictHunks.count == 1)
        #expect(vm.conflictPicks.isEmpty)
    }
}
