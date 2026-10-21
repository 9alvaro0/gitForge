import Foundation
import Testing
@testable import gitForge

@Suite("Files tab selection")
@MainActor
struct PullRequestFilesTabSelectionTests {
    static func file(_ path: String) -> PullRequestFileChange {
        PullRequestFileChange(path: path, oldPath: nil, status: .modified, additions: 1, deletions: 0, patch: nil)
    }

    @Test("A file still in the list stays selected")
    func keeps() {
        let files = [Self.file("a.swift"), Self.file("b.swift")]
        #expect(PullRequestFilesTab.selection(keeping: "b.swift", ids: files.map(\.path), files: files) == "b.swift")
        #expect(PullRequestFilesTab.selection(keeping: PullRequestFilesTab.otherCommentsID,
                                              ids: [PullRequestFilesTab.otherCommentsID] + files.map(\.path),
                                              files: files) == PullRequestFilesTab.otherCommentsID)
    }

    @Test("Another PR's file, or none, falls back to the first file, not Other comments")
    func fallsBack() {
        let files = [Self.file("a.swift"), Self.file("b.swift")]
        let ids = [PullRequestFilesTab.otherCommentsID] + files.map(\.path)
        #expect(PullRequestFilesTab.selection(keeping: "specs/tech.md", ids: ids, files: files) == "a.swift")
        #expect(PullRequestFilesTab.selection(keeping: nil, ids: ids, files: files) == "a.swift")
    }

    @Test("Only Other comments: that row; nothing listed: nothing")
    func edges() {
        #expect(PullRequestFilesTab.selection(keeping: "x", ids: [PullRequestFilesTab.otherCommentsID], files: [])
                == PullRequestFilesTab.otherCommentsID)
        #expect(PullRequestFilesTab.selection(keeping: "x", ids: [], files: []) == nil)
    }
}
