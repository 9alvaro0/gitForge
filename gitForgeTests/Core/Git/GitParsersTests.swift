import Foundation
import Testing
@testable import gitForge

/// Parsers of git plumbing output that had no direct tests (audit A09).
@Suite("Git output parsers")
struct GitParsersTests {

    // MARK: for-each-ref

    @Test("parseRefs: branches, remotes and HEAD marker")
    func refsKinds() {
        let out = """
        aaa\t\trefs/heads/main\t*
        bbb\t\trefs/heads/feature/x\t
        ccc\t\trefs/remotes/origin/main\t
        ddd\t\trefs/remotes/origin/HEAD\t
        """
        let refs = GitCLI.parseRefs(out)
        #expect(refs.map(\.name) == ["main", "feature/x", "origin/main"])
        #expect(refs[0].isLocalBranch && refs[0].isHead)
        #expect(!refs[1].isHead)
        #expect(refs[2].isRemoteBranch)
    }

    @Test("parseRefs: annotated tags point at the dereferenced commit")
    func refsAnnotatedTag() {
        let out = """
        tagobj\tcommitsha\trefs/tags/v1.0\t
        light\t\trefs/tags/v0.9\t
        """
        let refs = GitCLI.parseRefs(out)
        #expect(refs.map(\.targetSha) == ["commitsha", "light"])
        #expect(refs.allSatisfy { $0.isTag })
    }

    @Test("parseRefs ignores malformed lines and unknown namespaces")
    func refsMalformed() {
        let refs = GitCLI.parseRefs("garbage\nsha\t\trefs/notes/commits\t\n")
        #expect(refs.isEmpty)
    }

    // MARK: stash list

    @Test("parseStashes reads index, sha and subject (tabs in the subject survive)")
    func stashes() {
        let out = "s0\tstash@{0}\tWIP on main: 123 fix\ttabs\ns1\tstash@{1}\tOn dev: note\n"
        let stashes = GitCLI.parseStashes(out)
        #expect(stashes.map(\.index) == [0, 1])
        #expect(stashes.map(\.sha) == ["s0", "s1"])
        #expect(stashes[0].subject == "WIP on main: 123 fix\ttabs")
    }

    @Test("parseStashes skips entries without a numeric index")
    func stashesMalformed() {
        #expect(GitCLI.parseStashes("s0\tstash@{x}\tsubject\nbroken line\n").isEmpty)
    }

    @Test("parseStashFiles merges name-status with numstat, renames included")
    func stashFiles() {
        let files = GitCLI.parseStashFiles(
            nameStatus: "M\ta.txt\nR100\told.txt\tnew.txt\nD\tgone.txt\n",
            numstat: "3\t1\ta.txt\n-\t-\tnew.txt\n0\t5\tgone.txt\n"
        )
        #expect(files.map(\.path) == ["a.txt", "new.txt", "gone.txt"])
        #expect(files[0].additions == 3 && files[0].deletions == 1)
        #expect(files[1].status == .renamed && files[1].oldPath == "old.txt")
        #expect(files[1].additions == 0) // binary numstat "-"
        #expect(files[2].status == .deleted && files[2].deletions == 5)
    }

    // MARK: diff-tree name-status

    @Test("parseNameStatus maps every status letter, renames and copies keep their source")
    func nameStatus() {
        let out = "A\tnew.txt\nM\tmod.txt\nD\tdel.txt\nR087\tfrom.txt\tto.txt\nC100\tsrc.txt\tcopy.txt\nT\tlink\nX\tweird\n"
        let changes = GitCLI.parseNameStatus(out)
        #expect(changes.map(\.path) == ["new.txt", "mod.txt", "del.txt", "to.txt", "copy.txt", "link", "weird"])
        #expect(changes[3].status == .renamed(from: "from.txt"))
        #expect(changes[4].status == .copied(from: "src.txt"))
        #expect(changes[6].status == .unknown("X"))
    }

    // MARK: clone URL validation (security gate)

    @Test("Accepted clone URLs", arguments: [
        "https://github.com/a/b.git", "http://host/repo", "ssh://git@host/repo",
        "git://host/repo", "git@github.com:a/b.git", "  https://github.com/a/b  ",
    ])
    func cloneURLAccepted(url: String) throws {
        let validated = try CloneURLValidator.validate(url)
        #expect(validated == url.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    @Test("Rejected clone URLs", arguments: [
        ("", CloneURLValidator.Failure.empty),
        ("   ", .empty),
        ("--upload-pack=touch /tmp/pwned", .startsWithDash),
        ("-oProxyCommand=evil", .startsWithDash),
        ("file:///etc", .unsupportedScheme("file:///etc")),
        ("/Users/me/repo", .unsupportedScheme("/Users/me/repo")),
        ("@host:path", .unsupportedScheme("@host:path")),
        ("host:path@x", .unsupportedScheme("host:path@x")),
    ])
    func cloneURLRejected(url: String, failure: CloneURLValidator.Failure) {
        #expect(throws: failure) { try CloneURLValidator.validate(url) }
    }
}
