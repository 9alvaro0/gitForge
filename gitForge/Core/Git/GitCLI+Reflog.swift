import Foundation

extension GitCLI {
    /// Entries read per reflog: about three months of a busy day's work.
    static let reflogLimit = 300

    /// Commit fields (as in `log`), then the selector with `--date=unix`
    /// (`HEAD@{1794341196}`: when the ref moved) and git's reflog subject.
    /// Unit separators between fields, NUL between entries (`-z`).
    private static let reflogFormat = "%H%x1f%P%x1f%an%x1f%ae%x1f%aI%x1f%gd%x1f%gs%x1f%s"

    /// `ref`'s reflog, newest first: `HEAD` or a full ref such as
    /// `refs/heads/main`. Reads one entry past `limit` so the last one still
    /// knows where the ref was before it. A ref with no reflog yet (an
    /// unborn `HEAD`, a branch made without one) or one that no longer
    /// exists (deleted meanwhile) reads as empty.
    func reflog(of ref: String = "HEAD", limit: Int = GitCLI.reflogLimit) async throws -> [ReflogEntry] {
        // `--no-show-signature`: `log.showSignature=true` would print gpg's
        // output into stdout, between the entries.
        let args = ["log", "-g", "-z", "--no-show-signature", "--date=unix",
                    "--format=\(Self.reflogFormat)", "-n", String(limit + 1),
                    Self.endOfOptions, ref, "--"]
        let result: GitResult
        do {
            result = try await run(args)
        } catch let error as GitError {
            guard case .commandFailed = error, await !resolves(ref) else { throw error }
            return []
        }
        return Self.parseReflog(result.stdout, limit: limit)
    }

    /// Whether `ref` names a commit (an unborn `HEAD` doesn't).
    private func resolves(_ ref: String) async -> Bool {
        (try? await run(["rev-parse", "--verify", "--quiet", Self.endOfOptions, "\(ref)^{commit}"])) != nil
    }

    static func parseReflog(_ stdout: String, limit: Int = reflogLimit) -> [ReflogEntry] {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withTimeZone]

        struct Raw { let commit: Commit; let date: Date; let message: String }
        let raws: [Raw] = stdout.split(separator: "\0", omittingEmptySubsequences: true).compactMap { record in
            // `-z` ends each record with NUL; git may still put a newline
            // between them.
            let line = record.trimmingCharacters(in: .newlines)
            let parts = line.split(separator: "\u{1F}", omittingEmptySubsequences: false)
            guard parts.count >= 8 else { return nil }
            let sha = String(parts[0])
            guard sha.count >= 40, sha.allSatisfy(\.isHexDigit) else { return nil }
            let commit = Commit(
                sha: sha,
                parentShas: parts[1].split(separator: " ").map(String.init),
                authorName: String(parts[2]),
                authorEmail: String(parts[3]),
                authorDate: formatter.date(from: String(parts[4])) ?? unknownAuthorDate,
                subject: parts[7...].joined(separator: "\u{1F}")
            )
            return Raw(commit: commit, date: reflogDate(parts[5]) ?? commit.authorDate, message: String(parts[6]))
        }

        return raws.prefix(limit).enumerated().map { index, raw in
            ReflogEntry(
                index: index,
                movedTo: raw.commit,
                movedFrom: index + 1 < raws.count ? raws[index + 1].commit : nil,
                date: raw.date,
                message: raw.message,
                action: ReflogAction.parse(raw.message)
            )
        }
    }

    /// The time in a `--date=unix` selector: `HEAD@{1794341196}`.
    private static func reflogDate(_ selector: Substring) -> Date? {
        guard let open = selector.range(of: "@{", options: .backwards),
              let close = selector[open.upperBound...].firstIndex(of: "}"),
              let seconds = TimeInterval(selector[open.upperBound..<close]) else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    /// The commits reachable from `shas` that no ref reaches (branches,
    /// tags, remote branches, the stash, HEAD), each with its parents: what
    /// recovering those entries would bring back.
    func unreachableCommits(from shas: [String]) async throws -> [String: [String]] {
        var seen = Set<String>()
        let unique = shas.filter { $0.allSatisfy(\.isHexDigit) && seen.insert($0).inserted }
        guard !unique.isEmpty else { return [:] }
        let result = try await run(["rev-list", "--parents"] + unique + ["--not", "--all"])
        return Self.parseParents(result.stdout)
    }

    /// `rev-list --parents` lines: `<sha> <parent> <parent>…`.
    static func parseParents(_ stdout: String) -> [String: [String]] {
        var graph: [String: [String]] = [:]
        for line in stdout.split(separator: "\n") {
            let shas = line.split(separator: " ").map(String.init)
            guard let sha = shas.first else { continue }
            graph[sha] = Array(shas.dropFirst())
        }
        return graph
    }
}

/// What recovering a reflog entry brings back.
nonisolated enum ReflogRecovery {
    /// For each of `shas`, how many commits it reaches that no ref does
    /// (`unreachable`, from `GitCLI.unreachableCommits`). 0 for a commit
    /// that is already on a branch or tag.
    static func lostCounts(for shas: [String], unreachable: [String: [String]]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for sha in shas where counts[sha] == nil {
            guard unreachable[sha] != nil else {
                counts[sha] = 0
                continue
            }
            var visited: Set<String> = [sha]
            var stack = [sha]
            while let next = stack.popLast() {
                for parent in unreachable[next] ?? [] where unreachable[parent] != nil && visited.insert(parent).inserted {
                    stack.append(parent)
                }
            }
            counts[sha] = visited.count
        }
        return counts
    }
}
