import Testing
@testable import gitForge

@Suite("File status badges")
@MainActor
struct FileStatusBadgeTests {

    @Test("A working-copy file shows its staged change when it has one, else its unstaged one")
    func displayStatus() {
        let partial = WorkingCopyFile(path: "a", stagedStatus: .added, unstagedStatus: .modified, originalPath: nil)
        let unstaged = WorkingCopyFile(path: "b", stagedStatus: .unmodified, unstagedStatus: .deleted, originalPath: nil)
        let untracked = WorkingCopyFile(path: "c", stagedStatus: .untracked, unstagedStatus: .untracked, originalPath: nil)
        #expect(partial.displayStatus == .added)
        #expect(unstaged.displayStatus == .deleted)
        #expect(untracked.displayStatus == .untracked)
    }

    @Test("Unmodified collapses to M so a partially-staged side still gets a badge")
    func unmodifiedCollapses() {
        #expect(StatusTag.Kind(workingFile: .unmodified) == .modified)
    }

    @Test("Every file model maps a rename and a catch-all to the same badges")
    func mappings() {
        #expect(StatusTag.Kind(commitFile: .renamed(from: "x")) == .renamed)
        #expect(StatusTag.Kind(commitFile: .unknown("X")) == .modified)
        #expect(StatusTag.Kind(stashFile: .untracked) == .untracked)
        #expect(StatusTag.Kind(stashFile: .other("X")) == .modified)
        #expect(StatusTag.Kind(pullRequestFile: .renamed) == .renamed)
        #expect(StatusTag.Kind(pullRequestFile: .other("X")) == .modified)
    }
}
