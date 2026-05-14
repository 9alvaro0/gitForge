import Foundation
import Testing
@testable import gitForge

/// Validates the NUL-separated porcelain-v2 parser. Synthesizes the exact
/// bytes git emits for each entry type — easier than running git in a temp
/// repo and covers exotic paths git wouldn't reproduce on demand.
@Suite("GitCLI.parseStatus — porcelain v2 -z")
struct GitCLIStatusParserTests {

    /// Builds a stdout blob from individual records joined by NUL. Each
    /// trailing NUL is included so the parser sees the same shape git emits.
    private func makeStdout(_ records: [String]) -> String {
        records.joined(separator: "\u{0}") + "\u{0}"
    }

    @Test("Empty output → empty file list")
    func emptyOutput() {
        #expect(GitCLI.parseStatus("").isEmpty)
    }

    @Test("Single modified file (type 1)")
    func singleModified() {
        // `1 .M N... 100644 100644 100644 hh1 hh2 path/to/file.swift`
        let record = "1 .M N... 100644 100644 100644 0000000 0000000 path/to/file.swift"
        let files = GitCLI.parseStatus(makeStdout([record]))
        #expect(files.count == 1)
        #expect(files.first?.path == "path/to/file.swift")
        #expect(files.first?.unstagedStatus == .modified)
        #expect(files.first?.stagedStatus == .unmodified)
    }

    @Test("Path with embedded newline (the whole reason we moved to -z)")
    func pathWithNewline() {
        let weirdPath = "weird\nname.txt"
        let record = "1 .M N... 100644 100644 100644 0000000 0000000 \(weirdPath)"
        let files = GitCLI.parseStatus(makeStdout([record]))
        #expect(files.count == 1)
        #expect(files.first?.path == weirdPath)
    }

    @Test("Path with embedded tab")
    func pathWithTab() {
        let weirdPath = "tabbed\tpath.txt"
        let record = "1 .M N... 100644 100644 100644 0000000 0000000 \(weirdPath)"
        let files = GitCLI.parseStatus(makeStdout([record]))
        #expect(files.count == 1)
        #expect(files.first?.path == weirdPath)
    }

    @Test("Path with spaces stays intact (maxSplits guarantees the last field absorbs spaces)")
    func pathWithSpaces() {
        let record = "1 .M N... 100644 100644 100644 0000000 0000000 path with spaces.txt"
        let files = GitCLI.parseStatus(makeStdout([record]))
        #expect(files.count == 1)
        #expect(files.first?.path == "path with spaces.txt")
    }

    @Test("Rename (type 2) reads the next record as origPath")
    func renameEntry() {
        // `2 R. ... new-path` then a separate record with the old path.
        let record1 = "2 R. N... 100644 100644 100644 0000000 0000000 R100 new-path.txt"
        let record2 = "old-path.txt"
        let files = GitCLI.parseStatus(makeStdout([record1, record2]))
        #expect(files.count == 1)
        #expect(files.first?.path == "new-path.txt")
        #expect(files.first?.originalPath == "old-path.txt")
        #expect(files.first?.stagedStatus == .renamed)
    }

    @Test("Untracked entry (type ?)")
    func untrackedEntry() {
        let record = "? new-file.txt"
        let files = GitCLI.parseStatus(makeStdout([record]))
        #expect(files.count == 1)
        #expect(files.first?.path == "new-file.txt")
        #expect(files.first?.unstagedStatus == .untracked)
    }

    @Test("Untracked path with NUL-only separator and weird chars works")
    func untrackedWithSpaces() {
        let record = "? new file with spaces.txt"
        let files = GitCLI.parseStatus(makeStdout([record]))
        #expect(files.first?.path == "new file with spaces.txt")
    }

    @Test("Unmerged entry (type u)")
    func unmergedEntry() {
        let record = "u UU N... 100644 100644 100644 100644 0000000 0000000 0000000 conflict.txt"
        let files = GitCLI.parseStatus(makeStdout([record]))
        #expect(files.count == 1)
        #expect(files.first?.path == "conflict.txt")
        #expect(files.first?.isUnmerged == true)
    }

    @Test("Ignored entry (type !) is dropped")
    func ignoredEntry() {
        let record = "! ignored.txt"
        let files = GitCLI.parseStatus(makeStdout([record]))
        #expect(files.isEmpty)
    }

    @Test("Mixed batch: modified + untracked + renamed in one blob")
    func mixedBatch() {
        let stdout = makeStdout([
            "1 .M N... 100644 100644 100644 0000000 0000000 modified.txt",
            "2 R. N... 100644 100644 100644 0000000 0000000 R100 newname.txt",
            "oldname.txt",
            "? added.txt",
        ])
        let files = GitCLI.parseStatus(stdout)
        #expect(files.count == 3)
        #expect(files.contains { $0.path == "modified.txt" })
        #expect(files.contains { $0.path == "newname.txt" && $0.originalPath == "oldname.txt" })
        #expect(files.contains { $0.path == "added.txt" })
    }

    @Test("Malformed record (type 1 with too few fields) is silently skipped")
    func malformedEntrySkipped() {
        let stdout = makeStdout([
            "1 .M too few fields here",
            "? real-untracked.txt",
        ])
        let files = GitCLI.parseStatus(stdout)
        // The malformed entry drops out, the valid one stays.
        #expect(files.contains { $0.path == "real-untracked.txt" })
    }
}
