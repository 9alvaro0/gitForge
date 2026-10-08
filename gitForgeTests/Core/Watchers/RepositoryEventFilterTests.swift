import Foundation
import Testing
@testable import gitForge

@Suite("RepositoryEventFilter")
struct RepositoryEventFilterTests {

    private let filter = RepositoryEventFilter(worktree: "/Users/me/repo",
                                               gitDirectories: ["/Users/me/repo/.git"])

    @Test("Any worktree file is relevant")
    func worktreeFiles() {
        #expect(filter.isRelevant("/Users/me/repo/Sources/App.swift"))
        #expect(filter.isRelevant("/Users/me/repo/README.md"))
    }

    @Test("Paths outside the repository are ignored")
    func outsidePaths() {
        #expect(!filter.isRelevant("/Users/me/repo-other/file.txt"))
        #expect(!filter.isRelevant("/Users/me/repo"))
    }

    @Test("Published git state is relevant, nested refs included")
    func gitState() {
        for path in ["HEAD", "packed-refs", "refs/heads/main", "refs/heads/feature/login",
                     "refs/remotes/origin/feature/x", "refs/tags/v1.0", "refs/stash",
                     "MERGE_HEAD", "CHERRY_PICK_HEAD", "REVERT_HEAD", "BISECT_LOG",
                     "rebase-merge", "rebase-merge/done", "rebase-apply/next"] {
            #expect(filter.isRelevant("/Users/me/repo/.git/" + path), "\(path)")
        }
    }

    @Test("Git internals our own reads touch are ignored (no refresh loop)")
    func gitNoise() {
        for path in ["index", "index.lock", "HEAD.lock", "refs/heads/main.lock",
                     "objects/ab/cdef", "logs/HEAD", "FETCH_HEAD", "ORIG_HEAD",
                     "COMMIT_EDITMSG", "config", "modules/sub/HEAD"] {
            #expect(!filter.isRelevant("/Users/me/repo/.git/" + path), "\(path)")
        }
        #expect(!filter.isRelevant("/Users/me/repo/.git"))
    }

    @Test("Linked worktree: per-worktree gitdir and common dir both filtered")
    func linkedWorktree() {
        let linked = RepositoryEventFilter(
            worktree: "/Users/me/wt",
            gitDirectories: ["/Users/me/repo/.git", "/Users/me/repo/.git/worktrees/wt"]
        )
        #expect(linked.isRelevant("/Users/me/repo/.git/worktrees/wt/HEAD"))
        #expect(!linked.isRelevant("/Users/me/repo/.git/worktrees/wt/index"))
        #expect(linked.isRelevant("/Users/me/repo/.git/refs/heads/feature/x"))
        #expect(linked.isRelevant("/Users/me/wt/file.txt"))
    }

    @Test("Matching is case-insensitive and tolerates trailing slashes")
    func normalisation() {
        let mixed = RepositoryEventFilter(worktree: "/Users/Me/Repo/", gitDirectories: ["/Users/Me/Repo/.git/"])
        #expect(mixed.isRelevant("/users/me/repo/.git/HEAD"))
        #expect(!mixed.isRelevant("/users/me/repo/.git/index"))
    }

    @Test("A rescan batch is relevant even with only ignorable paths")
    func rescan() {
        let noise = FileEventStream.Batch(paths: ["/Users/me/repo/.git/index"], mustRescan: false)
        let rescan = FileEventStream.Batch(paths: ["/Users/me/repo/.git/index"], mustRescan: true)
        #expect(!filter.isRelevant(noise))
        #expect(filter.isRelevant(rescan))
    }
}
