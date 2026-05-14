import Foundation
import Testing
@testable import gitForge

/// Diff content that legitimately contains lines starting with `@@` or
/// `diff --git`: think a repo versioning patches under `tests/fixtures/*.patch`,
/// or a Markdown doc with literal git output. The parser must not mistake the
/// in-hunk content for a new hunk/file header — the leading sigil (+/-/ )
/// is what tells the difference.
@Suite("DiffParser — patch-shaped content inside hunks")
struct DiffParserPatchedContentTests {

    @Test("`+@@ -1,1 +1,1 @@` as added content does NOT terminate the hunk")
    func addedAtAtLine() {
        // Real diff over a file that gained a hunk-header-shaped line.
        let diff = """
        @@ -1,3 +1,4 @@
         keep
        +@@ -1,1 +1,1 @@
         end
        """
        let hunks = DiffParser.parse(diff)
        #expect(hunks.count == 1)
        // The "+@@ ..." line must be parsed as a normal added line, not as a
        // new hunk header that breaks the original hunk's body.
        let added = hunks.first?.lines.filter { $0.kind == .added } ?? []
        #expect(added.map(\.content) == ["@@ -1,1 +1,1 @@"])
    }

    @Test("`+diff --git ...` as added content does NOT terminate the hunk")
    func addedDiffGitLine() {
        let diff = """
        @@ -1,3 +1,4 @@
         line1
        +diff --git a/x b/x
         line2
        """
        let hunks = DiffParser.parse(diff)
        #expect(hunks.count == 1)
        let added = hunks.first?.lines.filter { $0.kind == .added } ?? []
        #expect(added.map(\.content) == ["diff --git a/x b/x"])
    }

    @Test("Context line that visually looks like `@@` (with leading space) stays inside the hunk")
    func contextAtAtLine() {
        let diff = """
        @@ -1,4 +1,4 @@
         alpha
         @@ -1,1 +1,1 @@
         beta
        -delta
        +gamma
        """
        let hunks = DiffParser.parse(diff)
        #expect(hunks.count == 1)
        // Verify the context line is preserved with its content intact.
        let contextContents = hunks.first?.lines
            .filter { $0.kind == .context }
            .map(\.content) ?? []
        #expect(contextContents.contains("@@ -1,1 +1,1 @@"))
    }

    @Test("A genuine second `@@` header DOES open a second hunk")
    func realSecondHunkHeaderStartsNewHunk() {
        let diff = """
        @@ -1,1 +1,1 @@
        -a
        +b
        @@ -10,1 +10,1 @@
        -c
        +d
        """
        let hunks = DiffParser.parse(diff)
        #expect(hunks.count == 2)
    }

    @Test("A genuine `diff --git` between hunks DOES end the previous hunk")
    func realDiffGitBetweenFilesEndsHunk() {
        let diff = """
        @@ -1,1 +1,1 @@
        -a
        +b
        diff --git a/y b/y
        index 1111111..2222222 100644
        --- a/y
        +++ b/y
        @@ -1,1 +1,1 @@
        -c
        +d
        """
        let hunks = DiffParser.parse(diff)
        #expect(hunks.count == 2)
    }
}
