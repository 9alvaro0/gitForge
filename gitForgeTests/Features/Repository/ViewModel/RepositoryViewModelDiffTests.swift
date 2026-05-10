import Foundation
import Testing
@testable import gitForge

@Suite("RepositoryViewModel.synthesizeAddDiff")
struct SynthesizeAddDiffTests {

    @Test("Empty input emits an empty string")
    func emptyInput() {
        #expect(RepositoryViewModel.synthesizeAddDiff(text: "") == "")
    }

    @Test("Single line without trailing newline appends the no-newline marker")
    func singleLineNoNewline() {
        let out = RepositoryViewModel.synthesizeAddDiff(text: "hello")
        #expect(out.hasPrefix("@@ -0,0 +1,1 @@\n"))
        #expect(out.contains("+hello\n"))
        #expect(out.hasSuffix("\\ No newline at end of file\n"))
    }

    @Test("Single line with trailing newline omits the no-newline marker")
    func singleLineWithNewline() {
        let out = RepositoryViewModel.synthesizeAddDiff(text: "hello\n")
        #expect(out == "@@ -0,0 +1,1 @@\n+hello\n")
    }

    @Test("Multi-line input keeps each line as a + line")
    func multiLine() {
        let out = RepositoryViewModel.synthesizeAddDiff(text: "a\nb\nc\n")
        #expect(out == "@@ -0,0 +1,3 @@\n+a\n+b\n+c\n")
    }

    @Test("Multi-line without trailing newline appends the marker")
    func multiLineNoTrailingNewline() {
        let out = RepositoryViewModel.synthesizeAddDiff(text: "a\nb")
        #expect(out.hasPrefix("@@ -0,0 +1,2 @@\n"))
        #expect(out.contains("+a\n+b"))
        #expect(out.hasSuffix("\\ No newline at end of file\n"))
    }
}

@Suite("RepositoryViewModel.classifyEmptyDiff")
struct ClassifyEmptyDiffTests {

    @Test("Detects 'Binary files' marker")
    func detectsBinary() {
        #expect(RepositoryViewModel.classifyEmptyDiff(raw: "Binary files a and b differ") == .binary)
    }

    @Test("Detects 'GIT binary patch' marker")
    func detectsBinaryPatch() {
        let raw = "diff --git a/foo b/foo\nGIT binary patch\nliteral 1024\n..."
        #expect(RepositoryViewModel.classifyEmptyDiff(raw: raw) == .binary)
    }

    @Test("Detects 'rename from' header at start of output")
    func detectsRenameAtStart() {
        let raw = "rename from old.swift\nrename to new.swift\n"
        #expect(RepositoryViewModel.classifyEmptyDiff(raw: raw) == .renameOnly)
    }

    @Test("Detects 'rename from' header in the middle of output")
    func detectsRenameInside() {
        let raw = """
        diff --git a/old b/new
        similarity index 100%
        rename from old
        rename to new
        """
        #expect(RepositoryViewModel.classifyEmptyDiff(raw: raw) == .renameOnly)
    }

    @Test("Falls back to .empty when no recognised markers are present")
    func fallsBackToEmpty() {
        #expect(RepositoryViewModel.classifyEmptyDiff(raw: "") == .empty)
        #expect(RepositoryViewModel.classifyEmptyDiff(raw: "diff --git a/x b/x\n") == .empty)
    }
}

@Suite("RepositoryViewModel — detail cache", .serialized)
@MainActor
struct RepositoryViewModelDetailCacheTests {

    private static func makeVM() -> RepositoryViewModel {
        let url = URL(fileURLWithPath: "/var/empty/gitForge-tests-\(UUID().uuidString)")
        return RepositoryViewModel(repository: Repository(url: url))
    }

    private static func makeDetail(sha: String) -> CommitDetail {
        let commit = Commit(
            sha: sha,
            parentShas: [],
            authorName: "Test",
            authorEmail: "t@example.com",
            authorDate: .init(timeIntervalSince1970: 0),
            subject: "subject"
        )
        return CommitDetail(commit: commit, fullMessage: "body", files: [])
    }

    @Test("cacheDetail stores the entry and exposes it through detailCache")
    func storesEntries() {
        let vm = Self.makeVM()
        let detail = Self.makeDetail(sha: "aaa")
        vm.cacheDetail(detail, for: "aaa")
        #expect(vm.detailCache["aaa"] == detail)
    }

    @Test("cacheDetail re-inserting the same sha doesn't duplicate the order entry")
    func reInsertingDoesNotDuplicate() {
        let vm = Self.makeVM()
        let d1 = Self.makeDetail(sha: "aaa")
        let d2 = Self.makeDetail(sha: "aaa")  // same sha, would be the same in production
        vm.cacheDetail(d1, for: "aaa")
        vm.cacheDetail(d2, for: "aaa")
        #expect(vm.detailCache.count == 1)
    }

    @Test("cacheDetail evicts oldest entries when the cap is exceeded")
    func evictsOldestWhenCapExceeded() {
        let vm = Self.makeVM()
        // The cap is 200; insert 210 entries and verify the first 10 are gone.
        for i in 0..<210 {
            vm.cacheDetail(Self.makeDetail(sha: "sha-\(i)"), for: "sha-\(i)")
        }
        #expect(vm.detailCache.count == 200)
        #expect(vm.detailCache["sha-0"] == nil)
        #expect(vm.detailCache["sha-9"] == nil)
        #expect(vm.detailCache["sha-10"] != nil)
        #expect(vm.detailCache["sha-209"] != nil)
    }
}
