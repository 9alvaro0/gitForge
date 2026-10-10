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

    @Test("parseRefs reads upstream, tracking, date and subject (tabs in the subject survive)")
    func refsTracking() {
        let out = """
        aaa\t\trefs/heads/main\t*\torigin/main\t[ahead 2, behind 3]\t1760000000\tFix\tthing
        bbb\t\trefs/heads/old\t\torigin/old\t[gone]\t1760000001\tOld work
        ccc\t\trefs/heads/local-only\t\t\t\t1760000002\tWIP
        ddd\t\trefs/remotes/origin/main\t\t\t\t1760000003\tRemote tip
        """
        let refs = GitCLI.parseRefs(out)
        #expect(refs[0].upstream == "origin/main")
        #expect(refs[0].ahead == 2 && refs[0].behind == 3)
        #expect(refs[0].subject == "Fix\tthing")
        #expect(refs[0].date == Date(timeIntervalSince1970: 1_760_000_000))
        #expect(refs[1].upstreamGone)
        #expect(refs[2].upstream == nil && refs[2].ahead == nil && refs[2].behind == nil)
        #expect(refs[3].subject == "Remote tip" && refs[3].upstream == nil)
    }

    @Test("parseRefs still reads the four-column format")
    func refsLegacyColumns() {
        let refs = GitCLI.parseRefs("aaa\t\trefs/heads/main\t*\n")
        #expect(refs.count == 1)
        #expect(refs[0].upstream == nil && refs[0].subject == nil && refs[0].date == nil)
    }

    @Test("UpstreamTrack parses ahead, behind, both, gone and in sync",
          arguments: [
            ("[ahead 2, behind 3]", 2, 3, false),
            ("[ahead 1]", 1, 0, false),
            ("[behind 4]", 0, 4, false),
            ("[gone]", 0, 0, true),
            ("", 0, 0, false),
          ])
    func track(raw: String, ahead: Int, behind: Int, gone: Bool) {
        #expect(UpstreamTrack.parse(raw) == UpstreamTrack(ahead: ahead, behind: behind, gone: gone))
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
