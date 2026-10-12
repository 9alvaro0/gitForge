import Foundation
import Testing
@testable import gitForge

@Suite("DiffParser — blank context lines")
struct DiffParserBlankLineTests {
    @Test("An empty line inside a hunk (diff.suppressBlankEmpty) is context and keeps the numbering")
    func suppressedBlank() throws {
        // Context "a", a blank line printed without its space, then a change.
        let diff = "diff --git a/x b/x\n--- a/x\n+++ b/x\n@@ -1,3 +1,3 @@\n a\n\n-b\n+c\n"
        let hunk = try #require(DiffParser.parse(diff).first)
        #expect(hunk.lines.map(\.kind) == [.context, .context, .removed, .added])
        #expect(hunk.lines[1].content == "")
        #expect(hunk.lines[1].oldLineNumber == 2)
        #expect(hunk.lines[2].oldLineNumber == 3)
        #expect(hunk.lines[3].newLineNumber == 3)
    }

    @Test("The trailing newline after a full hunk isn't a line")
    func trailingNewline() throws {
        let diff = "diff --git a/x b/x\n--- a/x\n+++ b/x\n@@ -1,1 +1,1 @@\n-a\n+b\n\n"
        let hunk = try #require(DiffParser.parse(diff).first)
        #expect(hunk.lines.count == 2)
    }

    @Test("A real repo whose config says suppressBlankEmpty still gets blank lines as context")
    func gitForcesBlankSpace() async throws {
        let repo = try await GitTestRepo.make { repo in
            try repo.commit("first", files: ["x.txt": "a\n\nb\n"])
            try repo.git("config", "diff.suppressBlankEmpty", "true")
            try repo.write("a\n\nc\n", to: "x.txt")
        }
        defer { repo.remove() }
        let output = try await repo.cli.diffUnstaged(file: "x.txt")
        let lines = try #require(DiffParser.parse(output).first).lines
        #expect(lines.contains { $0.kind == .context && $0.content.isEmpty && $0.oldLineNumber == 2 })
    }
}
