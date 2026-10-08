import Foundation
import Testing
@testable import gitForge

/// Output-shape regressions: undecodable bytes and user/repo config that
/// changes what `git diff` prints must not blank or corrupt the diff pane.
@Suite("GitCLI — output robustness", .serialized)
struct GitCLIOutputRobustnessTests {

    @Test("Lossy decode keeps valid text around an invalid UTF-8 byte")
    func lossyDecode() {
        let bytes = Data("caf".utf8) + Data([0xE9]) + Data("\nok\n".utf8)
        let decoded = GitProcess.decode(bytes)
        #expect(decoded.hasPrefix("caf"))
        #expect(decoded.hasSuffix("\nok\n"))
    }

    @Test("A Latin-1 byte in file content still yields a parsed diff")
    func latin1DiffIsNotEmpty() async throws {
        let repo = try GitTestRepo()
        defer { repo.remove() }
        try repo.commit("init", files: ["l.txt": "hola\n"])
        try repo.write(Data("hola\ncaf".utf8) + Data([0xE9]) + Data("\n".utf8), to: "l.txt")

        let raw = try await repo.cli.diffUnstaged(file: "l.txt")
        let hunks = DiffParser.parse(raw)
        #expect(hunks.count == 1)
        #expect(hunks.first?.lines.contains { $0.kind == .added } == true)
    }

    @Test("color.diff=always and diff.external in config don't leak into parsed diffs")
    func configDoesNotLeak() async throws {
        let repo = try GitTestRepo()
        defer { repo.remove() }
        let sha = try repo.commit("init", files: ["f.txt": "one\n"])
        try repo.git("config", "color.diff", "always")
        try repo.git("config", "diff.external", "/bin/echo")
        try repo.write("one\ntwo\n", to: "f.txt")

        let unstaged = try await repo.cli.diffUnstaged(file: "f.txt")
        #expect(!unstaged.contains("\u{1B}["))
        #expect(DiffParser.parse(unstaged).count == 1)

        try repo.git("add", "f.txt")
        let staged = try await repo.cli.diffStaged(file: "f.txt")
        #expect(DiffParser.parse(staged).count == 1)

        let committed = try await repo.cli.diff(sha: sha, file: "f.txt")
        #expect(!committed.contains("\u{1B}["))
        #expect(DiffParser.parse(committed).count == 1)
    }
}
