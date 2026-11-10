import Foundation
import Testing
@testable import gitForge

/// `GitCLI.reflog` over real reflogs: what each git action writes, and the
/// commit and words the Recover view shows for it.
@Suite("GitCLI.reflog", .serialized)
struct GitCLIReflogTests {

    private static func sha(_ repo: GitTestRepo, _ rev: String) async throws -> String {
        try await repo.gitAsync("rev-parse", rev).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Five commits on main: one … five.
    private static func fiveCommits() async throws -> GitTestRepo {
        try await GitTestRepo.make { repo in
            for n in ["one", "two", "three", "four", "five"] {
                try repo.commit(n, files: ["f.txt": n])
            }
        }
    }

    // MARK: Reset

    @Test("After reset --hard HEAD~3, the newest entry is the state before it, with the three commits a branch brings back")
    func resetHard() async throws {
        let repo = try await Self.fiveCommits()
        defer { repo.remove() }
        let five = try await Self.sha(repo, "HEAD")
        let two = try await Self.sha(repo, "HEAD~3")
        try await repo.gitAsync("reset", "-q", "--hard", "HEAD~3")

        let entries = try await repo.cli.reflog()
        let latest = try #require(entries.first)
        #expect(latest.action == .reset(target: "HEAD~3"))
        #expect(latest.movedTo.sha == two)
        #expect(latest.commit.sha == five)
        #expect(latest.commit.subject == "five")
        #expect(latest.title == "Before reset to \(two.prefix(7))")

        let unreachable = try await repo.cli.unreachableCommits(from: entries.map(\.commit.sha))
        let counts = ReflogRecovery.lostCounts(for: entries.map(\.commit.sha), unreachable: unreachable)
        #expect(counts[five] == 3)
        #expect(counts[two] == 0)

        // "Create branch here" on it: the three commits are on a branch again.
        try await repo.cli.createBranch(latest.suggestedBranchName(), startingAt: latest.commit.sha)
        let recovered = try await repo.gitAsync("log", "--format=%s", "main..\(latest.suggestedBranchName())")
        #expect(recovered.split(separator: "\n") == ["five", "four", "three"])
        let after = try await repo.cli.unreachableCommits(from: [five])
        #expect(after.isEmpty)
    }

    @Test("A reset as the oldest entry read, with nothing before it, offers where it moved to")
    func resetWithoutHistoryBeforeIt() async throws {
        let repo = try await Self.fiveCommits()
        defer { repo.remove() }
        try await repo.gitAsync("reset", "-q", "--hard", "HEAD~1")

        let entries = try await repo.cli.reflog(limit: 1)
        let only = try #require(entries.first)
        #expect(entries.count == 1)
        // One entry past the limit is read, so the reset still knows.
        #expect(only.showsPreviousState)
        #expect(only.commit.subject == "five")

        let all = GitCLI.parseReflog(
            ["\(only.movedTo.sha)\u{1F}\u{1F}T\u{1F}t@e.x\u{1F}2026-11-10T20:00:00+00:00\u{1F}HEAD@{1794341196}\u{1F}reset: moving to HEAD~1\u{1F}four"]
                .joined(separator: "\0"))
        #expect(all.first?.showsPreviousState == false)
        #expect(all.first?.title == "Reset to \(only.movedTo.shortSha)")
        #expect(all.first?.commit == all.first?.movedTo)
    }

    // MARK: Amend

    @Test("An amend offers the commit before it")
    func amend() async throws {
        let repo = try await Self.fiveCommits()
        defer { repo.remove() }
        let original = try await Self.sha(repo, "HEAD")
        try await repo.gitAsync("commit", "-q", "--amend", "-m", "five, reworded")

        let latest = try #require(try await repo.cli.reflog().first)
        #expect(latest.action == .amend)
        #expect(latest.title == "Before amend")
        #expect(latest.commit.sha == original)
        #expect(latest.commit.subject == "five")
        #expect(latest.movedTo.subject == "five, reworded")
    }

    // MARK: Rebase

    @Test("A rebase reads as its start (the branch before it), its steps and its finish (the rebased tip)")
    func rebase() async throws {
        let repo = try await GitTestRepo.make { repo in
            try repo.commit("base", files: ["f.txt": "base"])
            try repo.git("checkout", "-q", "-b", "feature")
            try repo.commit("f1", files: ["g.txt": "1"])
            try repo.commit("f2", files: ["g.txt": "2"])
            try repo.git("checkout", "-q", "main")
            try repo.commit("m1", files: ["h.txt": "1"])
            try repo.git("checkout", "-q", "feature")
        }
        defer { repo.remove() }
        let before = try await Self.sha(repo, "feature")
        try await repo.gitAsync("rebase", "-q", "main")
        let after = try await Self.sha(repo, "feature")

        let entries = try await repo.cli.reflog()
        let finish = try #require(entries.first)
        #expect(finish.action == .rebaseFinish(pull: false))
        #expect(finish.title == "Rebase finished")
        #expect(finish.commit.sha == after)

        let steps = entries.prefix { if case .rebaseStart = $0.action { false } else { true } }.dropFirst()
        #expect(steps.map(\.action) == [.rebaseStep(phase: "pick", pull: false), .rebaseStep(phase: "pick", pull: false)])
        #expect(steps.map(\.commit.subject) == ["f2", "f1"])
        #expect(steps.first?.title == "Rebase step (pick)")

        let start = try #require(entries.first { if case .rebaseStart = $0.action { true } else { false } })
        #expect(start.action == .rebaseStart(onto: "main", pull: false))
        #expect(start.title == "Before rebase onto main")
        #expect(start.commit.sha == before)
        #expect(start.commit.subject == "f2")

        let unreachable = try await repo.cli.unreachableCommits(from: entries.map(\.commit.sha))
        let counts = ReflogRecovery.lostCounts(for: [before], unreachable: unreachable)
        #expect(counts[before] == 2)
    }

    // MARK: Checkout

    @Test("Checkouts name where HEAD went: a branch by name, a detached commit by its short SHA")
    func checkout() async throws {
        let repo = try await Self.fiveCommits()
        defer { repo.remove() }
        let four = try await Self.sha(repo, "HEAD~1")
        try await repo.gitAsync("checkout", "-q", "-b", "feature")
        try await repo.gitAsync("checkout", "-q", "--detach", four)

        let entries = try await repo.cli.reflog()
        #expect(entries[0].action == .checkout(from: "feature", to: four))
        #expect(entries[0].title == "Checked out \(four.prefix(7))")
        #expect(entries[0].commit.sha == four)
        #expect(entries[1].action == .checkout(from: "main", to: "feature"))
        #expect(entries[1].title == "Checked out feature")
    }

    @Test("Commits made on a detached HEAD and left behind are found, and counted as lost")
    func detachedWork() async throws {
        let repo = try await Self.fiveCommits()
        defer { repo.remove() }
        try await repo.gitAsync("checkout", "-q", "--detach")
        let lost = try await repo.commitAsync("on detached", files: ["d.txt": "d"])
        try await repo.gitAsync("checkout", "-q", "main")

        let entries = try await repo.cli.reflog()
        let commit = try #require(entries.first { $0.commit.sha == lost })
        #expect(commit.action == .commit)
        #expect(commit.title == "Commit")
        let unreachable = try await repo.cli.unreachableCommits(from: entries.map(\.commit.sha))
        #expect(ReflogRecovery.lostCounts(for: [lost], unreachable: unreachable)[lost] == 1)
    }

    // MARK: Merge, cherry-pick, revert

    @Test("Merges, fast-forward or not, a merge committed after conflicts, a cherry-pick and a revert")
    func mergeCherryPickRevert() async throws {
        let repo = try await GitTestRepo.make { repo in
            try repo.commit("base", files: ["f.txt": "base"])
            try repo.git("checkout", "-q", "-b", "ff")
            try repo.commit("ff1", files: ["a.txt": "1"])
            try repo.git("checkout", "-q", "main")
            try repo.git("merge", "-q", "ff")
            try repo.git("checkout", "-q", "-b", "topic")
            try repo.commit("t1", files: ["b.txt": "1"])
            try repo.git("checkout", "-q", "main")
            try repo.commit("m1", files: ["c.txt": "1"])
            try repo.git("merge", "-q", "--no-edit", "topic")
            try repo.git("checkout", "-q", "-b", "clash", "HEAD~1")
            try repo.commit("clash", files: ["f.txt": "theirs"])
            try repo.git("checkout", "-q", "main")
            try repo.commit("ours", files: ["f.txt": "ours"])
            try repo.git(["merge", "-q", "clash"], allowFailure: true)
            try repo.write("resolved", to: "f.txt")
            try repo.git("add", "f.txt")
            try repo.git("commit", "-q", "--no-edit")
            try repo.git("checkout", "-q", "-b", "side", "main~2")
            try repo.commit("side", files: ["s.txt": "1"])
            try repo.git("checkout", "-q", "main")
            try repo.git("cherry-pick", "side")
            try repo.git("revert", "--no-edit", "HEAD")
        }
        defer { repo.remove() }

        let entries = try await repo.cli.reflog()
        let byAction = entries.map(\.action)
        #expect(byAction.prefix(2) == [.revert, .cherryPick])
        #expect(entries[0].title == "Revert")
        #expect(entries[0].commit.subject == "Revert \"side\"")
        #expect(entries[1].title == "Cherry-pick")
        #expect(entries[1].commit.subject == "side")
        #expect(byAction.contains(.mergeCommit))
        #expect(byAction.contains(.merge(branch: "topic", fastForward: false)))
        #expect(byAction.contains(.merge(branch: "ff", fastForward: true)))
        #expect(entries.contains { $0.title == "Merged topic" })
        #expect(entries.contains { $0.title == "Fast-forwarded to ff" })
        #expect(entries.contains { $0.title == "Merge commit" })
        #expect(entries.last?.action == .initialCommit)
        #expect(entries.last?.title == "Initial commit")
    }

    // MARK: A branch's reflog

    @Test("A branch's reflog: created, committed on, moved with branch -f, renamed")
    func branchReflog() async throws {
        let repo = try await Self.fiveCommits()
        defer { repo.remove() }
        let tipBefore = try await repo.perform { repo -> String in
            try repo.git("branch", "work", "HEAD~2")
            try repo.git("checkout", "-q", "work")
            let tip = try repo.commit("w1", files: ["w.txt": "1"])
            try repo.git("checkout", "-q", "main")
            try repo.git("branch", "-f", "work", "main")
            try repo.git("branch", "-m", "work", "renamed")
            return tip
        }

        let entries = try await repo.cli.reflog(of: "refs/heads/renamed")
        #expect(entries.map(\.action) == [
            .branchRenamed(from: "work", to: "renamed"),
            .branchReset(to: "main"),
            .commit,
            .branchCreated(from: "HEAD~2"),
        ])
        #expect(entries[0].title == "Renamed from work")
        #expect(entries[1].title == "Before branch moved to main")
        #expect(entries[1].commit.sha == tipBefore)
        #expect(entries[3].title == "Branch created from HEAD~2")
    }

    // MARK: Edges

    @Test("An unborn HEAD, a branch with no reflog and one deleted meanwhile read as empty")
    func edges() async throws {
        let empty = try await GitTestRepo.make()
        defer { empty.remove() }
        #expect(try await empty.cli.reflog().isEmpty)

        let repo = try await Self.fiveCommits()
        defer { repo.remove() }
        try await repo.gitAsync("-c", "core.logAllRefUpdates=false", "update-ref", "refs/heads/nolog", "HEAD")
        #expect(try await repo.cli.reflog(of: "refs/heads/nolog").isEmpty)
        #expect(try await repo.cli.reflog(of: "refs/heads/missing").isEmpty)
    }

    @Test("The entry's time is when the ref moved, not the commit's date")
    func reflogTime() async throws {
        let repo = try await Self.fiveCommits()
        defer { repo.remove() }
        try await repo.perform {
            try $0.git(["checkout", "-q", "-b", "later"], extraEnvironment: ["GIT_COMMITTER_DATE": "@1700000000 +0000"])
        }
        let latest = try #require(try await repo.cli.reflog().first)
        #expect(latest.date == Date(timeIntervalSince1970: 1_700_000_000))
        #expect(latest.date != latest.commit.authorDate)
    }

    @Test("Indexes count from the newest entry; `limit` keeps that many")
    func limit() async throws {
        let repo = try await Self.fiveCommits()
        defer { repo.remove() }
        let entries = try await repo.cli.reflog(limit: 3)
        #expect(entries.map(\.index) == [0, 1, 2])
        #expect(entries.map(\.commit.subject) == ["five", "four", "three"])
        #expect(entries.allSatisfy { $0.movedFrom != nil })
    }
}
