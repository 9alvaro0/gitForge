import Foundation
import Testing
@testable import gitForge

/// `ReflogAction.parse` over reflog subjects copied from real git output
/// (2.43 and the older forms still found in long-lived reflogs), and the
/// pure helpers around it.
@Suite("Reflog subjects")
struct ReflogActionTests {

    @Test("Commits: plain, initial, amend, merge and cherry-pick after conflicts", arguments: [
        ("commit: five", ReflogAction.commit),
        ("commit (initial): one", .initialCommit),
        ("commit (amend): six amended", .amend),
        ("commit (merge): Merge branch 'y'", .mergeCommit),
        ("commit (cherry-pick): m3", .cherryPick),
        ("cherry-pick: t1", .cherryPick),
        ("revert: Revert \"b\"", .revert),
    ])
    func commits(message: String, expected: ReflogAction) {
        #expect(ReflogAction.parse(message) == expected)
    }

    @Test("Moves of HEAD: reset, checkout, merge, pull, clone", arguments: [
        ("reset: moving to HEAD~3", ReflogAction.reset(target: "HEAD~3")),
        ("reset: moving to HEAD", .reset(target: "HEAD")),
        ("checkout: moving from main to feature", .checkout(from: "main", to: "feature")),
        ("checkout: moving from fea916bb149e37f8d106c2f241591c13d0bf05d7 to main",
         .checkout(from: "fea916bb149e37f8d106c2f241591c13d0bf05d7", to: "main")),
        ("merge feature: Fast-forward", .merge(branch: "feature", fastForward: true)),
        ("merge topic: Merge made by the 'ort' strategy.", .merge(branch: "topic", fastForward: false)),
        ("merge origin/main: Merge made by the 'recursive' strategy.", .merge(branch: "origin/main", fastForward: false)),
        ("pull: Fast-forward", .pull),
        ("pull -q: Fast-forward", .pull),
        ("pull: Merge made by the 'ort' strategy.", .pull),
        ("clone: from https://github.com/9alvaro0/gitForge.git", .clone),
    ])
    func moves(message: String, expected: ReflogAction) {
        #expect(ReflogAction.parse(message) == expected)
    }

    @Test("Rebases, plain, interactive, older git and pull --rebase", arguments: [
        ("rebase (start): checkout main", ReflogAction.rebaseStart(onto: "main", pull: false)),
        ("rebase (pick): f1", .rebaseStep(phase: "pick", pull: false)),
        ("rebase (reword): f1", .rebaseStep(phase: "reword", pull: false)),
        ("rebase (squash): f1", .rebaseStep(phase: "squash", pull: false)),
        ("rebase (continue): f1", .rebaseStep(phase: "continue", pull: false)),
        ("rebase: fast-forward", .rebaseStep(phase: "fast-forward", pull: false)),
        ("rebase (finish): returning to refs/heads/feature", .rebaseFinish(pull: false)),
        ("rebase (finish): refs/heads/feature onto 75c9a7924829229e6dcadea90fa1437c846de491", .rebaseFinish(pull: false)),
        ("rebase (abort): returning to refs/heads/y", .rebaseAbort(pull: false)),
        ("rebase -i (start): checkout HEAD~2", .rebaseStart(onto: "HEAD~2", pull: false)),
        ("rebase -i (finish): returning to refs/heads/main", .rebaseFinish(pull: false)),
        ("rebase finished: returning to refs/heads/main", .rebaseFinish(pull: false)),
        ("pull --rebase (start): checkout a66636ab70ef15779f5058aeb0d219dfaaaff8de",
         .rebaseStart(onto: "a66636ab70ef15779f5058aeb0d219dfaaaff8de", pull: true)),
        ("pull -q --rebase (pick): z", .rebaseStep(phase: "pick", pull: true)),
        ("pull -q --rebase (finish): returning to refs/heads/main", .rebaseFinish(pull: true)),
    ])
    func rebases(message: String, expected: ReflogAction) {
        #expect(ReflogAction.parse(message) == expected)
    }

    @Test("A branch's own reflog", arguments: [
        ("branch: Created from HEAD", ReflogAction.branchCreated(from: "HEAD")),
        ("branch: Created from main~2", .branchCreated(from: "main~2")),
        ("branch: Reset to main", .branchReset(to: "main")),
        ("Branch: renamed refs/heads/topic to refs/heads/topic2", .branchRenamed(from: "topic", to: "topic2")),
    ])
    func branch(message: String, expected: ReflogAction) {
        #expect(ReflogAction.parse(message) == expected)
    }

    @Test("Anything else is kept as git wrote it", arguments: [
        "am: Fix the thing", "update-ref: custom", "", "weird", "checkout: moving somewhere", "branch: something new",
    ])
    func other(message: String) {
        #expect(ReflogAction.parse(message) == .other)
        let entry = Self.entry(message)
        #expect(entry.title == message)
    }

    @Test("Only moves that leave work behind point at the commit before them")
    func leavesWorkBehind() {
        let behind: [ReflogAction] = [.amend, .reset(target: "HEAD~1"), .rebaseStart(onto: "main", pull: false),
                                      .rebaseStart(onto: "x", pull: true), .branchReset(to: "main")]
        let forward: [ReflogAction] = [.commit, .initialCommit, .mergeCommit, .cherryPick, .revert,
                                       .checkout(from: "a", to: "b"), .merge(branch: "x", fastForward: true),
                                       .rebaseStep(phase: "pick", pull: false), .rebaseFinish(pull: false),
                                       .rebaseAbort(pull: false), .pull, .clone, .branchCreated(from: "HEAD"),
                                       .branchRenamed(from: "a", to: "b"), .other]
        #expect(behind.allSatisfy { $0.leavesWorkBehind })
        #expect(forward.allSatisfy { !$0.leavesWorkBehind })
    }

    @Test("Titles read as what happened")
    func titles() {
        #expect(Self.entry("reset: moving to HEAD~3").title == "Before reset to bbbbbbb")
        #expect(Self.entry("commit (amend): x").title == "Before amend")
        #expect(Self.entry("rebase (finish): returning to refs/heads/feature").title == "Rebase finished")
        #expect(Self.entry("rebase (start): checkout refs/heads/main").title == "Before rebase onto main")
        #expect(Self.entry("pull --rebase (start): checkout \(Self.sha("c"))").title == "Before pull with rebase")
        #expect(Self.entry("pull --rebase (finish): returning to refs/heads/main").title == "Pull with rebase finished")
        #expect(Self.entry("rebase (abort): returning to refs/heads/y").title == "Rebase aborted")
        #expect(Self.entry("pull: Fast-forward").title == "Pull")
        #expect(Self.entry("clone: from x").title == "Cloned")
        #expect(Self.entry("checkout: moving from main to \(Self.sha("c"))").title == "Checked out ccccccc")
    }

    @Test("Display names: a full SHA shortened, refs/heads/ dropped, the rest kept")
    func display() {
        #expect(ReflogEntry.display(Self.sha("a")) == "aaaaaaa")
        #expect(ReflogEntry.display("refs/heads/feat/x") == "feat/x")
        #expect(ReflogEntry.display("HEAD~2") == "HEAD~2")
        #expect(ReflogEntry.display("refs/remotes/origin/main") == "refs/remotes/origin/main")
        #expect(ReflogEntry.display("abc") == "abc")
    }

    @Test("The suggested branch name is free")
    func suggestedName() {
        let entry = Self.entry("reset: moving to HEAD~1")
        #expect(entry.suggestedBranchName() == "recovered-aaaaaaa")
        #expect(entry.suggestedBranchName(avoiding: ["recovered-aaaaaaa"]) == "recovered-aaaaaaa-2")
        #expect(entry.suggestedBranchName(avoiding: ["recovered-aaaaaaa", "recovered-aaaaaaa-2"]) == "recovered-aaaaaaa-3")
        #expect(BranchValidator.isValidName(entry.suggestedBranchName()))
    }

    // MARK: Parsing git's output

    @Test("Records split on NUL, fields on the unit separator; a subject may hold one")
    func parseRecords() {
        let a = Self.sha("a"), b = Self.sha("b")
        let stdout = [
            [b, a, "Ann", "ann@x", "2026-11-10T20:00:00+00:00", "HEAD@{1794341196}", "commit: two", "two\u{1F}still two"],
            [a, "", "Ann", "ann@x", "2026-11-10T19:00:00+01:00", "HEAD@{1794337596}", "commit (initial): one", "one"],
            ["not-a-sha", "", "", "", "", "", "", ""],
            ["short"],
        ].map { $0.joined(separator: "\u{1F}") }.joined(separator: "\0") + "\0\n"

        let entries = GitCLI.parseReflog(stdout)
        #expect(entries.count == 2)
        #expect(entries[0].movedTo.subject == "two\u{1F}still two")
        #expect(entries[0].movedTo.parentShas == [a])
        #expect(entries[0].movedFrom?.sha == a)
        #expect(entries[0].date == Date(timeIntervalSince1970: 1_794_341_196))
        #expect(entries[1].movedTo.parentShas.isEmpty)
        #expect(entries[1].movedFrom == nil)
        #expect(entries[1].movedTo.authorDate == Date(timeIntervalSince1970: 1_794_333_600))
        #expect(entries[1].action == .initialCommit)
    }

    @Test("Lost counts: commits each entry reaches that no ref does, shared history counted for each")
    func lostCounts() {
        // a ← b ← c, and b ← d: c and d both reach b and a.
        let graph = ["c": ["b"], "b": ["a"], "a": ["root"], "d": ["b"]]
        let counts = ReflogRecovery.lostCounts(for: ["c", "d", "a", "root", "c"], unreachable: graph)
        #expect(counts == ["c": 3, "d": 3, "a": 1, "root": 0])
        #expect(GitCLI.parseParents("c b\nb a\na\n") == ["c": ["b"], "b": ["a"], "a": []])
    }

    // MARK: Helpers

    private static func sha(_ c: Character) -> String { String(repeating: c, count: 40) }

    private static func commit(_ c: Character, _ subject: String) -> Commit {
        Commit(sha: sha(c), parentShas: [], authorName: "T", authorEmail: "t@e.x",
               authorDate: Date(timeIntervalSince1970: 0), subject: subject)
    }

    /// An entry that moved from `a…` to `b…`.
    private static func entry(_ message: String) -> ReflogEntry {
        ReflogEntry(index: 0, movedTo: commit("b", "to"), movedFrom: commit("a", "from"),
                    date: Date(timeIntervalSince1970: 0), message: message, action: ReflogAction.parse(message))
    }
}
