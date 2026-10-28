import Foundation
import Testing
@testable import gitForge

@Suite("BlockedCheckout — the question's text")
struct BlockedCheckoutTests {

    private static func file(_ path: String) -> WorkingCopyFile {
        WorkingCopyFile(path: path, stagedStatus: .unmodified, unstagedStatus: .modified, originalPath: nil)
    }

    private static func branch(_ name: String, kind: GitRef.Kind = .localBranch) -> CheckoutTarget {
        .branch(GitRef(name: name, kind: kind, targetSha: "deadbeef", isHead: false))
    }

    private static func blocked(_ paths: [String], target: CheckoutTarget = branch("feature")) -> BlockedCheckout {
        BlockedCheckout(files: paths.map(file), target: target)
    }

    @Test("The title counts the files, singular and plural, and names the branch")
    func title() {
        #expect(Self.blocked(["a.txt"]).title == "Your changes to 1 file block checking out feature")
        #expect(Self.blocked(["a.txt", "b.txt"]).title == "Your changes to 2 files block checking out feature")
    }

    @Test("A remote branch is named as the local branch git checks out")
    func remoteBranchName() {
        let target = Self.branch("origin/feature", kind: .remoteBranch(remote: "origin"))
        #expect(target.displayName == "feature")
        #expect(target.successMessage == "Checked out feature")
    }

    @Test("A commit is named by its short SHA and detaches HEAD")
    func commitTarget() {
        let target = CheckoutTarget.commit(sha: "0123456789abcdef")
        #expect(Self.blocked(["a.txt"], target: target).title == "Your changes to 1 file block checking out 0123456")
        #expect(target.successMessage == "Detached HEAD at 0123456")
    }

    @Test("A pull request branch is named as is")
    func pullRequestTarget() {
        let target = CheckoutTarget.pullRequestBranch("fix/login")
        #expect(target.displayName == "fix/login")
        #expect(target.successMessage == "Checked out fix/login")
    }

    @Test("The message offers the way out, then lists the files one per line")
    func fewFiles() {
        let lines = Self.blocked(["a.txt", "dir/b.txt"]).message.split(separator: "\n").map(String.init)
        #expect(lines.first == "Checking out feature would overwrite them. Stash them to get them back later, or discard them:")
        #expect(Array(lines.dropFirst()) == ["a.txt", "dir/b.txt"])
    }

    @Test("Past ten files the rest are counted instead of listed")
    func manyFiles() {
        let paths = (1...12).map { "f\($0).txt" }
        let lines = Self.blocked(paths).message.split(separator: "\n").map(String.init)
        #expect(Array(lines.dropFirst()) == Array(paths.prefix(10)) + ["…and 2 more"])
    }

    @Test("The stash is named after the checkout it made way for")
    func stashMessage() {
        #expect(Self.blocked(["a.txt"]).stashMessage == "Before checking out feature")
    }
}
