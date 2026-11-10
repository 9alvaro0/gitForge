import Foundation
import Testing
@testable import gitForge

@Suite("RotatingLogFile")
struct RotatingLogFileTests {
    private func read(_ url: URL) -> String {
        (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    @Test("Creates the folder and the file on first write, private to the user")
    func createsPrivateFile() throws {
        let dir = TemporaryDirectories.make("rotating-log").appendingPathComponent("Logs/gitForge")
        let file = RotatingLogFile(directory: dir, maxFileBytes: 1_000, archiveCount: 2)
        try file.append("one\n")
        #expect(read(file.currentURL) == "one\n")
        let dirMode = try FileManager.default.attributesOfItem(atPath: dir.path)[.posixPermissions] as? Int
        let fileMode = try FileManager.default.attributesOfItem(atPath: file.currentURL.path)[.posixPermissions] as? Int
        #expect(dirMode == 0o700)
        #expect(fileMode == 0o600)
    }

    @Test("Rotates before a write would exceed the limit and keeps archiveCount archives")
    func rotates() throws {
        let dir = TemporaryDirectories.make("rotating-log")
        let file = RotatingLogFile(directory: dir, maxFileBytes: 10, archiveCount: 2)
        for line in ["aaaa\n", "bbbb\n", "cccc\n", "dddd\n", "eeee\n", "ffff\n", "gggg\n"] {
            try file.append(line)
        }
        // 10 bytes per file = two 5-byte lines; 7 lines → a-b dropped, c-d, e-f, g.
        #expect(read(file.currentURL) == "gggg\n")
        #expect(read(file.archiveURL(1)) == "eeee\nffff\n")
        #expect(read(file.archiveURL(2)) == "cccc\ndddd\n")
        #expect(!FileManager.default.fileExists(atPath: file.archiveURL(3).path))
        #expect(file.filesOldestFirst == [file.archiveURL(2), file.archiveURL(1), file.currentURL])
    }

    @Test("Total size stays bounded by maxFileBytes × (archiveCount + 1)")
    func bounded() throws {
        let dir = TemporaryDirectories.make("rotating-log")
        let file = RotatingLogFile(directory: dir, maxFileBytes: 200, archiveCount: 3)
        for index in 0..<1_000 { try file.append("entry \(index) with some padding\n") }
        let sizes = try file.filesOldestFirst.map {
            try FileManager.default.attributesOfItem(atPath: $0.path)[.size] as? Int ?? 0
        }
        #expect(sizes.count == 4)
        #expect(sizes.allSatisfy { $0 <= 200 })
        #expect(read(file.currentURL).contains("entry 999 "))
    }

    @Test("Appends to an existing file and counts its size across launches")
    func resumesExistingFile() throws {
        let dir = TemporaryDirectories.make("rotating-log")
        try RotatingLogFile(directory: dir, maxFileBytes: 12, archiveCount: 1).append("12345678\n")
        let reopened = RotatingLogFile(directory: dir, maxFileBytes: 12, archiveCount: 1)
        try reopened.append("abcdefgh\n")
        #expect(read(reopened.archiveURL(1)) == "12345678\n")
        #expect(read(reopened.currentURL) == "abcdefgh\n")
    }

    @Test("A file deleted while open is recreated instead of writing into the void")
    func recreatesDeletedFile() throws {
        let dir = TemporaryDirectories.make("rotating-log")
        let file = RotatingLogFile(directory: dir, maxFileBytes: 1_000, archiveCount: 1)
        try file.append("before\n")
        try FileManager.default.removeItem(at: dir)
        try file.append("after\n")
        #expect(read(file.currentURL) == "after\n")
    }

    @Test("With no archives, rotation starts the file over")
    func noArchives() throws {
        let dir = TemporaryDirectories.make("rotating-log")
        let file = RotatingLogFile(directory: dir, maxFileBytes: 6, archiveCount: 0)
        try file.append("1111\n")
        try file.append("2222\n")
        #expect(read(file.currentURL) == "2222\n")
        #expect(file.filesOldestFirst == [file.currentURL])
    }
}
