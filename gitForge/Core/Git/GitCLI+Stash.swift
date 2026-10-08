import Foundation

extension GitCLI {
    func stashes() async throws -> [Stash] {
        let result = try await run(["stash", "list", "--format=%H%x09%gd%x09%gs"])
        return Self.parseStashes(result.stdout)
    }

    static func parseStashes(_ stdout: String) -> [Stash] {
        stdout.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
            let parts = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
            guard parts.count == 3 else { return nil }
            let sha = String(parts[0])
            let ref = String(parts[1])
            let subject = String(parts[2])
            guard let openBrace = ref.firstIndex(of: "{"),
                  let closeBrace = ref.firstIndex(of: "}"),
                  closeBrace > ref.index(after: openBrace),
                  let index = Int(ref[ref.index(after: openBrace)..<closeBrace]) else {
                return nil
            }
            return Stash(index: index, sha: sha, subject: subject)
        }
    }

    func stashApply(index: Int, drop: Bool = false) async throws {
        let action = drop ? "pop" : "apply"
        try await run(["stash", action, "stash@{\(index)}"])
    }

    func stashDrop(index: Int) async throws {
        try await run(["stash", "drop", "stash@{\(index)}"])
    }

    /// Undoes a conflicted `git stash apply/pop`. git has no `--abort` for
    /// stash, and the tree is NOT necessarily clean beforehand: apply only
    /// refuses when local changes overlap the stash's paths. The previous
    /// `reset --hard HEAD` therefore wiped unrelated staged and unstaged work.
    ///
    /// With the stash SHA known, only the paths that stash touched are
    /// restored to HEAD — git guarantees none of them carried local changes
    /// before the apply:
    ///   • tracked paths present in HEAD → `git checkout HEAD --` (resets index
    ///     and worktree, unmerged entries included);
    ///   • paths the stash added (absent from HEAD) → dropped from the index
    ///     and sent to the Trash;
    ///   • untracked files restored from the stash's third parent → Trash.
    ///
    /// Without the SHA (app relaunched mid-conflict) it falls back to
    /// `git reset --merge`, which still keeps unstaged local changes.
    func stashAbortApply(stashSha: String?) async throws {
        guard let stashSha else {
            _ = try await run(["reset", "--merge"])
            return
        }
        let touched = try await stashTouchedPaths(sha: stashSha)
        let inHead = try await pathsPresentInHead(touched.tracked)
        let addedByStash = touched.tracked.filter { !inHead.contains($0) }

        if !inHead.isEmpty {
            try await run(["checkout", "HEAD", "--"] + touched.tracked.filter(inHead.contains))
        }
        if !addedByStash.isEmpty {
            try await run(["rm", "-q", "--cached", "-f", "--ignore-unmatch", "--"] + addedByStash)
        }
        try await deleteUntracked(paths: addedByStash + touched.untracked)
    }

    /// Paths a stash changes relative to its base. `--no-renames` so a rename
    /// reports both sides. Untracked files (only present when stashed with
    /// `--include-untracked`) live in the stash's third parent.
    func stashTouchedPaths(sha: String) async throws -> (tracked: [String], untracked: [String]) {
        let diff = try await run(["diff", "--name-only", "-z", "--no-renames"]
                                 + Self.diffOutputFlags + [Self.endOfOptions, "\(sha)^1", sha])
        let tracked = Self.splitNul(diff.stdout)
        let untrackedRef = "\(sha)^3"
        guard (try? await run(["rev-parse", "--verify", "--quiet", Self.endOfOptions, untrackedRef])) != nil else {
            return (tracked, [])
        }
        let tree = try await run(["ls-tree", "-r", "-z", "--name-only", Self.endOfOptions, untrackedRef])
        return (tracked, Self.splitNul(tree.stdout))
    }

    private func pathsPresentInHead(_ paths: [String]) async throws -> Set<String> {
        guard !paths.isEmpty else { return [] }
        let result = try await run(["ls-tree", "-r", "-z", "--name-only", "HEAD", "--"] + paths)
        return Set(Self.splitNul(result.stdout))
    }

    static func splitNul(_ output: String) -> [String] {
        output.split(separator: "\0", omittingEmptySubsequences: true).map(String.init)
    }

    func stashPush(message: String? = nil, includeUntracked: Bool = true) async throws {
        var args = ["stash", "push"]
        if includeUntracked { args.append("--include-untracked") }
        if let message, !message.isEmpty {
            args.append("-m")
            args.append(message)
        }
        try await run(args)
    }

    /// Files changed in `stash@{index}` compared to its first parent, plus
    /// any untracked files it saved (third parent). Combines `--name-status`
    /// (status letter + path) and `--numstat` (additions/deletions per path)
    /// since git can't emit both in a single `diff` pass cleanly.
    func stashFiles(index: Int) async throws -> [StashFileChange] {
        let ref = "stash@{\(index)}"
        async let names = run(["diff", "--name-status"] + Self.diffOutputFlags + ["\(ref)^", ref])
        async let numstat = run(["diff", "--numstat"] + Self.diffOutputFlags + ["\(ref)^", ref])
        async let untracked = untrackedStashNumstat(ref: ref)
        let (n, s, u) = try await (names, numstat, untracked)
        return Self.parseStashFiles(nameStatus: n.stdout, numstat: s.stdout)
            + Self.parseUntrackedStashFiles(numstat: u)
    }

    /// Unified diff for one file in `stash@{index}`. Untracked files have no
    /// base in the stash, so they're shown from the third parent (a root
    /// commit — `show` diffs it against the empty tree). Caller parses with
    /// `DiffParser`.
    func stashFileDiff(index: Int, path: String, untracked: Bool = false) async throws -> String {
        let ref = "stash@{\(index)}"
        let args: [String] = untracked
            ? ["show", "--format="] + Self.diffOutputFlags + [Self.endOfOptions, "\(ref)^3", "--", path]
            : ["diff"] + Self.diffOutputFlags + ["\(ref)^", ref, "--", path]
        return try await run(args).stdout
    }

    /// `--numstat` of the stash's untracked-files commit, or "" when the
    /// stash was created without `--include-untracked`.
    private func untrackedStashNumstat(ref: String) async throws -> String {
        let untrackedRef = "\(ref)^3"
        guard (try? await run(["rev-parse", "--verify", "--quiet", Self.endOfOptions, untrackedRef])) != nil else {
            return ""
        }
        return try await run(["show", "--numstat", "--format="] + Self.diffOutputFlags
                             + [Self.endOfOptions, untrackedRef]).stdout
    }

    static func parseUntrackedStashFiles(numstat: String) -> [StashFileChange] {
        numstat.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
            let parts = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
            guard parts.count == 3 else { return nil }
            return StashFileChange(path: String(parts[2]), oldPath: nil, status: .untracked,
                                   additions: Int(parts[0]) ?? 0, deletions: 0)
        }
    }

    /// Parent SHA (the HEAD when stashed) and the stash's author date.
    func stashParent(index: Int) async throws -> (parentSha: String, authorDate: Date?) {
        let ref = "stash@{\(index)}"
        let result = try await run(["log", "-1", "--format=%H%x09%aI", "\(ref)^"])
        let trimmed = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return (parentSha: trimmed, authorDate: nil) }
        let formatter = ISO8601DateFormatter()
        return (parentSha: String(parts[0]), authorDate: formatter.date(from: String(parts[1])))
    }

    static func parseStashFiles(nameStatus: String, numstat: String) -> [StashFileChange] {
        var stats: [String: (additions: Int, deletions: Int)] = [:]
        for line in numstat.split(separator: "\n", omittingEmptySubsequences: true) {
            let parts = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
            guard parts.count == 3 else { continue }
            // Binary files surface as "-\t-\t<path>" — count both as zero.
            let adds = Int(parts[0]) ?? 0
            let dels = Int(parts[1]) ?? 0
            stats[String(parts[2])] = (adds, dels)
        }
        var out: [StashFileChange] = []
        for line in nameStatus.split(separator: "\n", omittingEmptySubsequences: true) {
            let parts = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard let raw = parts.first else { continue }
            let code = raw.first.map(String.init) ?? ""
            let (status, path, oldPath): (StashFileChange.Status, String, String?)
            switch code {
            case "M": guard parts.count >= 2 else { continue }; status = .modified;    path = parts[1]; oldPath = nil
            case "A": guard parts.count >= 2 else { continue }; status = .added;       path = parts[1]; oldPath = nil
            case "D": guard parts.count >= 2 else { continue }; status = .deleted;     path = parts[1]; oldPath = nil
            case "T": guard parts.count >= 2 else { continue }; status = .typeChanged; path = parts[1]; oldPath = nil
            case "R": guard parts.count >= 3 else { continue }; status = .renamed;     path = parts[2]; oldPath = parts[1]
            case "C": guard parts.count >= 3 else { continue }; status = .copied;      path = parts[2]; oldPath = parts[1]
            default:  guard parts.count >= 2 else { continue }; status = .other(raw);  path = parts[1]; oldPath = nil
            }
            let stat = stats[path] ?? (0, 0)
            out.append(StashFileChange(
                path: path, oldPath: oldPath, status: status,
                additions: stat.additions, deletions: stat.deletions
            ))
        }
        return out
    }
}
