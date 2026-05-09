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

    func stashPush(message: String? = nil, includeUntracked: Bool = true) async throws {
        var args = ["stash", "push"]
        if includeUntracked { args.append("--include-untracked") }
        if let message, !message.isEmpty {
            args.append("-m")
            args.append(message)
        }
        try await run(args)
    }

    /// Files changed in `stash@{index}` compared to its first parent.
    /// Combines `--name-status` (status letter + path) and `--numstat`
    /// (additions/deletions per path) since git can't emit both in a single
    /// `diff` pass cleanly.
    func stashFiles(index: Int) async throws -> [StashFileChange] {
        let ref = "stash@{\(index)}"
        async let names = run(["diff", "--name-status", "\(ref)^", ref])
        async let numstat = run(["diff", "--numstat", "\(ref)^", ref])
        let (n, s) = try await (names, numstat)
        return Self.parseStashFiles(nameStatus: n.stdout, numstat: s.stdout)
    }

    /// Unified diff for one file in `stash@{index}`. Caller parses with
    /// `DiffParser`.
    func stashFileDiff(index: Int, path: String) async throws -> String {
        let ref = "stash@{\(index)}"
        let result = try await run(["diff", "\(ref)^", ref, "--", path])
        return result.stdout
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
