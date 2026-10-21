import Foundation
import Testing
@testable import gitForge

@Suite("BlockingLocalChanges — what stopped a pull")
struct BlockingLocalChangesTests {

    @Test("A merge or fast-forward pull names every file in the way, across git's blocks")
    func mergeBlocks() {
        // Verbatim from git 2.54 (`git pull --ff-only`): staged and unstaged
        // changes come in separate blocks, untracked files in a third.
        let stderr = """
            From /tmp/origin
               7cb7a31..b8f36fb  main       -> origin/main
            error: Your local changes to the following files would be overwritten by merge:
            \tadded.txt
            \tstaged.txt
            Please commit your changes or stash them before you merge.
            error: Your local changes to the following files would be overwritten by merge:
            \ta.txt
            Please commit your changes or stash them before you merge.
            error: The following untracked working tree files would be overwritten by merge:
            \tdir/x.txt
            \tn.txt
            Please move or remove them before you merge.
            Aborting
            Updating 7cb7a31..b8f36fb
            """
        #expect(BlockingLocalChanges(stderr: stderr) == .paths(["added.txt", "staged.txt", "a.txt", "dir/x.txt", "n.txt"]))
    }

    @Test("Paths keep their inner and trailing spaces")
    func spacesInPaths() {
        let stderr = """
            error: Your local changes to the following files would be overwritten by merge:
            \tmy notes.txt\u{20}
            Please commit your changes or stash them before you merge.
            Aborting
            """
        #expect(BlockingLocalChanges(stderr: stderr) == .paths(["my notes.txt "]))
    }

    @Test("Tab-indented lines outside a blocking list are not paths")
    func unrelatedTabLines() {
        let stderr = """
            hint: something\tunrelated
            \tnot-a-path.txt
            error: The following untracked working tree files would be overwritten by merge:
            \tn.txt
            Please move or remove them before you merge.
            Aborting
            """
        #expect(BlockingLocalChanges(stderr: stderr) == .paths(["n.txt"]))
    }

    @Test("A rebase pull refuses over any tracked change without naming files",
          arguments: [
            "error: cannot pull with rebase: You have unstaged changes.\nerror: Please commit or stash them.\n",
            "error: cannot pull with rebase: Your index contains uncommitted changes.\nerror: Please commit or stash them.\n",
          ])
    func rebase(stderr: String) {
        #expect(BlockingLocalChanges(stderr: stderr) == .allTrackedChanges)
    }

    @Test("Failures that aren't local changes in the way are not recognised",
          arguments: [
            "fatal: unable to access 'https://example.com/r.git/': Could not resolve host: example.com\n",
            "fatal: Not possible to fast-forward, aborting.\n",
            "CONFLICT (content): Merge conflict in a.txt\nAutomatic merge failed; fix conflicts and then commit the result.\n",
          ])
    func otherFailures(stderr: String) {
        #expect(BlockingLocalChanges(stderr: stderr) == nil)
    }

    @Test("Reads git's stderr out of a failed command, and nothing else")
    func fromError() {
        let blocked = GitError.commandFailed(args: ["pull"], exitCode: 128,
                                             stderr: "error: cannot pull with rebase: You have unstaged changes.\n")
        #expect(BlockingLocalChanges(error: blocked) == .allTrackedChanges)
        #expect(BlockingLocalChanges(error: GitError.busy) == nil)
        #expect(BlockingLocalChanges(error: CancellationError()) == nil)
    }
}
