import Foundation
import Testing
@testable import gitForge

/// Validates the `parseSummary` helper that surfaces non-hunk metadata.
/// Without it the UI rendered "no diff" for binary files, renames, mode
/// changes, and submodule pointer bumps — hiding real work.
@Suite("DiffParser — summary metadata")
struct DiffParserSummaryTests {

    @Test("nil for a plain text diff with hunks")
    func plainDiffReturnsNilSummary() {
        let diff = """
        diff --git a/x b/x
        index 1111111..2222222 100644
        --- a/x
        +++ b/x
        @@ -1,1 +1,1 @@
        -a
        +b
        """
        #expect(DiffParser.parseSummary(diff) == nil)
    }

    @Test("Detects a binary file diff")
    func detectsBinary() {
        let diff = """
        diff --git a/logo.png b/logo.png
        index 1111111..2222222 100644
        Binary files a/logo.png and b/logo.png differ
        """
        #expect(DiffParser.parseSummary(diff) == .binary(oldPath: "logo.png", newPath: "logo.png"))
    }

    @Test("Detects a rename with similarity index")
    func detectsRenameWithSimilarity() {
        let diff = """
        diff --git a/old.txt b/new.txt
        similarity index 95%
        rename from old.txt
        rename to new.txt
        """
        #expect(DiffParser.parseSummary(diff) == .rename(from: "old.txt", to: "new.txt", similarity: 95))
    }

    @Test("Detects a rename without similarity index (100% similarity → git omits it)")
    func detectsRenameWithoutSimilarity() {
        let diff = """
        diff --git a/old.txt b/new.txt
        rename from old.txt
        rename to new.txt
        """
        #expect(DiffParser.parseSummary(diff) == .rename(from: "old.txt", to: "new.txt", similarity: nil))
    }

    @Test("Detects a mode-only change (chmod +x)")
    func detectsModeChange() {
        let diff = """
        diff --git a/script.sh b/script.sh
        old mode 100644
        new mode 100755
        """
        #expect(DiffParser.parseSummary(diff) == .modeChange(from: "100644", to: "100755"))
    }

    @Test("Detects a submodule pointer bump")
    func detectsSubmoduleBump() {
        let diff = """
        diff --git a/vendor/foo b/vendor/foo
        index aaaaaaa..bbbbbbb 160000
        --- a/vendor/foo
        +++ b/vendor/foo
        @@ -1 +1 @@
        -Subproject commit aaaaaaa1234
        +Subproject commit bbbbbbb5678
        """
        #expect(DiffParser.parseSummary(diff) == .submoduleUpdate(
            path: "vendor/foo",
            from: "aaaaaaa1234",
            to: "bbbbbbb5678"
        ))
    }

    @Test("Empty input → nil summary")
    func emptyInput() {
        #expect(DiffParser.parseSummary("") == nil)
    }
}
