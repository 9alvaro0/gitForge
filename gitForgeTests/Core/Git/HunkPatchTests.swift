import Foundation
import Testing
@testable import gitForge

@Suite("HunkPatch")
struct HunkPatchTests {

    /// `-13 +B +C` with three lines of context each side.
    private static let hunk: DiffHunk = DiffParser.parse("""
    @@ -10,6 +10,7 @@
     10
     11
     12
    -13
    +B
    +C
     14
     15
    """)[0]

    private static func body(_ patch: String?) -> [String] {
        Array((patch ?? "").split(separator: "\n", omittingEmptySubsequences: false).dropFirst(3)).map(String.init)
    }

    @Test("A whole hunk keeps every line, with a file header")
    func wholeHunk() throws {
        let patch = try #require(HunkPatch.make(path: "sp ace.txt", hunk: Self.hunk))
        #expect(patch.hasPrefix("diff --git a/sp ace.txt b/sp ace.txt\n--- a/sp ace.txt\n+++ b/sp ace.txt\n"))
        #expect(Self.body(patch) == ["@@ -10,6 +10,7 @@", " 10", " 11", " 12", "-13", "+B", "+C", " 14", " 15", ""])
    }

    @Test("Staging picked lines drops unpicked + and keeps unpicked - as context")
    func forwardSelection() {
        // Ids: 0-2 context, 3 = -13, 4 = +B, 5 = +C.
        let patch = HunkPatch.make(path: "f", hunk: Self.hunk, selectedLineIds: [4])
        #expect(Self.body(patch) == ["@@ -10,6 +10,7 @@", " 10", " 11", " 12", " 13", "+B", " 14", " 15", ""])
    }

    @Test("Reverse patches keep unpicked + as context and drop unpicked -")
    func reverseSelection() {
        let patch = HunkPatch.make(path: "f", hunk: Self.hunk, selectedLineIds: [5], reverse: true)
        #expect(Self.body(patch) == ["@@ -10,6 +10,7 @@", " 10", " 11", " 12", " B", "+C", " 14", " 15", ""])
    }

    @Test("A selection with no change makes no patch")
    func emptySelection() {
        #expect(HunkPatch.make(path: "f", hunk: Self.hunk, selectedLineIds: []) == nil)
        #expect(HunkPatch.make(path: "f", hunk: Self.hunk, selectedLineIds: [0, 1]) == nil)
    }

    @Test("The no-newline marker follows its line")
    func noNewline() {
        let hunk = DiffParser.parse("""
        @@ -1,2 +1,2 @@
         a
        -b
        \\ No newline at end of file
        +c
        \\ No newline at end of file
        """)[0]
        // Stage only `+c`: `-b` stays as context, so both markers stay.
        let forward = HunkPatch.make(path: "f", hunk: hunk, selectedLineIds: [3])
        #expect(Self.body(forward).filter { $0.hasPrefix("\\") }.count == 2)
        // Reverse with only `-b` picked: the unpicked `+c` becomes context.
        let reverse = HunkPatch.make(path: "f", hunk: hunk, selectedLineIds: [1], reverse: true)
        #expect(Self.body(reverse).contains("-b"))
        #expect(Self.body(reverse).contains(" c"))
    }

    @Test("hasNoContext spots -U0 patches")
    func noContext() {
        #expect(HunkPatch.hasNoContext("diff --git a/f b/f\n--- a/f\n+++ b/f\n@@ -1 +1 @@\n-a\n+b\n"))
        #expect(!HunkPatch.hasNoContext("diff --git a/f b/f\n--- a/f\n+++ b/f\n@@ -1,2 +1,2 @@\n x\n-a\n+b\n"))
    }
}
