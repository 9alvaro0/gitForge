import Foundation

extension GitCLI {
    private static let logSeparator = "\u{1F}"
    private static let logFormat = "%H\u{1F}%P\u{1F}%an\u{1F}%ae\u{1F}%aI\u{1F}%s"

    /// Loads commits visible in the graph. The default scope mirrors GitKraken's
    /// out-of-the-box view: every local branch (`--branches`), the current HEAD
    /// (covers detached states), and any stash commits the caller passes in via
    /// `refs`. Remote-tracking refs and tags are intentionally excluded — pulling
    /// those via `--all` is what made the layout engine allocate one column per
    /// simultaneously open tip in dense histories.
    /// Pass `refs: ["--branches", "HEAD", stashSha1, "origin/develop", ...]` to
    /// override or extend the scope.
    func log(limit: Int = 200, skip: Int = 0, refs: [String] = ["--branches", "HEAD"]) async throws -> [Commit] {
        var args: [String] = ["log", "--topo-order", "--format=\(Self.logFormat)", "-n", String(limit)]
        if skip > 0 {
            args.append("--skip")
            args.append(String(skip))
        }
        args.append(contentsOf: refs)
        let result = try await run(args)
        return Self.parseLog(result.stdout)
    }

    /// Sentinel used when an `%aI` value fails to parse: epoch zero. Anchors
    /// the commit at the very bottom of any sort-by-date order instead of
    /// inheriting `Date()` (now), which would float it to the top and
    /// silently distort the log.
    static let unknownAuthorDate = Date(timeIntervalSince1970: 0)

    static func parseLog(_ stdout: String) -> [Commit] {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds, .withTimeZone]
        let fallback = ISO8601DateFormatter()
        fallback.formatOptions = [.withInternetDateTime]

        return stdout.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
            let parts = line.split(separator: Character(logSeparator), omittingEmptySubsequences: false)
            guard parts.count >= 6 else { return nil }
            let sha = String(parts[0])
            let parents = parts[1].isEmpty ? [] : parts[1].split(separator: " ").map { String($0) }
            let authorName = String(parts[2])
            let authorEmail = String(parts[3])
            let dateString = String(parts[4])
            let date = formatter.date(from: dateString)
                ?? fallback.date(from: dateString)
                ?? unknownAuthorDate
            let subject = parts[5...].joined(separator: logSeparator)
            return Commit(
                sha: sha,
                parentShas: parents,
                authorName: authorName,
                authorEmail: authorEmail,
                authorDate: date,
                subject: subject
            )
        }
    }

    func commitDetail(for commit: Commit) async throws -> CommitDetail {
        async let bodyResult = run(["log", "-1", "--format=%B", Self.endOfOptions, commit.sha])
        // `--root` lists the initial commit's files (diff-tree prints nothing
        // for a parentless commit otherwise); `--diff-merges=first-parent`
        // shows what a merge brought in relative to the branch it landed on
        // (plain diff-tree prints nothing for merges, and `-m` lists the diff
        // against every parent). Matches `diff(sha:file:)` below.
        async let filesResult = run(["diff-tree", "--no-commit-id", "--name-status", "-r",
                                     "--root", "--diff-merges=first-parent"]
                                    + Self.diffOutputFlags + [Self.endOfOptions, commit.sha])
        let body = try await bodyResult
        let files = try await filesResult
        return CommitDetail(
            commit: commit,
            fullMessage: body.stdout,
            files: Self.parseNameStatus(files.stdout)
        )
    }

    static func parseNameStatus(_ stdout: String) -> [CommitFileChange] {
        stdout.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
            let parts = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard let raw = parts.first else { return nil }
            let code = String(raw)
            let firstChar = code.first.map(String.init) ?? ""

            switch firstChar {
            case "A":
                guard parts.count >= 2 else { return nil }
                return CommitFileChange(path: String(parts[1]), status: .added)
            case "M":
                guard parts.count >= 2 else { return nil }
                return CommitFileChange(path: String(parts[1]), status: .modified)
            case "D":
                guard parts.count >= 2 else { return nil }
                return CommitFileChange(path: String(parts[1]), status: .deleted)
            case "R":
                guard parts.count >= 3 else { return nil }
                return CommitFileChange(path: String(parts[2]), status: .renamed(from: String(parts[1])))
            case "C":
                guard parts.count >= 3 else { return nil }
                return CommitFileChange(path: String(parts[2]), status: .copied(from: String(parts[1])))
            case "T":
                guard parts.count >= 2 else { return nil }
                return CommitFileChange(path: String(parts[1]), status: .typeChanged)
            case "U":
                guard parts.count >= 2 else { return nil }
                return CommitFileChange(path: String(parts[1]), status: .unmerged)
            default:
                guard parts.count >= 2 else { return nil }
                return CommitFileChange(path: String(parts[1]), status: .unknown(code))
            }
        }
    }

    /// Patch for one file in `sha`. `git show` diffs against the first parent
    /// for merges and against the empty tree for the root commit, so no
    /// parent probing or fallback is needed (the previous `sha^` + `try?`
    /// fallback also swallowed timeouts and oversize errors).
    func diff(sha: String, file: String) async throws -> String {
        let context = "-U\(AppTheme.persistedDiffContextLines())"
        let result = try await run(["show", "--format=", "--diff-merges=first-parent", context]
                                   + Self.diffOutputFlags + [Self.endOfOptions, sha, "--", file])
        return result.stdout
    }
}
