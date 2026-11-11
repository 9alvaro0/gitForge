import Foundation

extension GitCLI {
    /// Commit fields as in `log`, unit separators between them. With `-z`
    /// each record ends with NUL, and the `--name-status` lines after it are
    /// NUL-separated too: `\n<status>\0<path>\0[<new path>\0]`.
    private static let fileHistoryFormat = "%H%x1f%P%x1f%an%x1f%ae%x1f%aI%x1f%s"

    /// The newest `limit` commits that touched `path` on HEAD, following it
    /// across renames (`--follow`). An unborn HEAD has no history and reads
    /// as empty.
    ///
    /// Pages are read by asking for more from the top, not with `--skip`:
    /// `--follow` only notices a rename in a commit it shows, so a page that
    /// skipped over the rename went on looking for the new name and stopped.
    ///
    /// `--follow` goes by path: a file deleted and later recreated under the
    /// same name lists the old file's commits after the deletion.
    func fileHistory(path: String, limit: Int) async throws -> [FileHistoryEntry] {
        // `--no-show-signature`: `log.showSignature=true` would print gpg's
        // output between the records. `-M`: rename detection for the
        // name-status lines, whatever `diff.renames` says.
        var args = ["log", "--follow", "-z", "--no-show-signature", "--name-status", "-M",
                    "--format=\(Self.fileHistoryFormat)", "-n", String(limit)]
        args += Self.diffOutputFlags + [Self.endOfOptions, "HEAD", "--", path]
        let result: GitResult
        do {
            result = try await run(args)
        } catch let error as GitError {
            guard case .commandFailed = error,
                  (try? await run(["rev-parse", "--verify", "--quiet", "HEAD^{commit}"])) == nil else { throw error }
            return []
        }
        return Self.parseFileHistory(result.stdout, path: path)
    }

    /// Parses `fileHistory`'s output. Each commit's record is followed by
    /// its name-status entry for the file, if git printed one (it prints none
    /// for a merge). `path` names entries git gave no path for.
    static func parseFileHistory(_ stdout: String, path: String) -> [FileHistoryEntry] {
        let tokens = stdout.split(separator: "\0", omittingEmptySubsequences: false)
        var entries: [FileHistoryEntry] = []
        var index = 0
        // The path of the entry above, for one with no name-status: older
        // entries keep the name the file had at the newer one.
        var currentPath = path
        while index < tokens.count {
            let record = tokens[index]
            index += 1
            guard let commit = parseFileHistoryCommit(record) else { continue }
            var status: CommitFileChange.Status?
            var entryPath = currentPath
            // A name-status entry starts with the newline git puts after the record.
            if index < tokens.count, let code = nameStatusCode(tokens[index]) {
                index += 1
                let pathCount = code.first == "R" || code.first == "C" ? 2 : 1
                if index + pathCount <= tokens.count {
                    let paths = tokens[index..<(index + pathCount)].map(String.init)
                    index += pathCount
                    let line = ([code] + paths).joined(separator: "\t")
                    if let change = parseNameStatus(line).first {
                        status = change.status
                        entryPath = change.path
                    }
                }
            }
            entries.append(FileHistoryEntry(commit: commit, path: entryPath, status: status))
            // Before a rename, the file had its old name.
            if case .renamed(let from) = status { currentPath = from } else { currentPath = entryPath }
        }
        return entries
    }

    /// The status letters of a name-status token (`\nM`, `\nR100`), or nil
    /// when `token` is something else (the next commit's record).
    private static func nameStatusCode(_ token: Substring) -> String? {
        let code = token.trimmingCharacters(in: .newlines)
        guard token.first == "\n" || token.first == "\r",
              let letter = code.first, "AMDRCTUXB".contains(letter),
              code.dropFirst().allSatisfy(\.isNumber) else { return nil }
        return code
    }

    private static func parseFileHistoryCommit(_ record: Substring) -> Commit? {
        let line = record.trimmingCharacters(in: .newlines)
        let parts = line.split(separator: "\u{1F}", omittingEmptySubsequences: false)
        guard parts.count >= 6 else { return nil }
        let sha = String(parts[0])
        guard sha.count >= 40, sha.allSatisfy(\.isHexDigit) else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withTimeZone]
        return Commit(
            sha: sha,
            parentShas: parts[1].split(separator: " ").map(String.init),
            authorName: String(parts[2]),
            authorEmail: String(parts[3]),
            authorDate: formatter.date(from: String(parts[4])) ?? unknownAuthorDate,
            subject: parts[5...].joined(separator: "\u{1F}")
        )
    }

    /// The patch of `path` in `sha` alone. With `previousPath` (the commit
    /// renamed or copied the file) both paths are in the pathspec, so git
    /// pairs them and shows the changes instead of a whole new file.
    func fileHistoryDiff(sha: String, path: String, previousPath: String?) async throws -> String {
        let context = "-U\(GitPreferences.diffContextLines)"
        let paths = [path] + (previousPath.map { [$0] } ?? [])
        let result = try await run(["show", "--format=", "--diff-merges=first-parent", "-M", context]
                                   + Self.diffOutputFlags + GitPreferences.diffWhitespaceArgs
                                   + [Self.endOfOptions, sha, "--"] + paths)
        return result.stdout
    }

    /// Paths of the tracked files (the index), sorted as git lists them, for
    /// ⌘K's file history rows. At most `limit`. A conflicted file is listed
    /// once, not once per stage.
    func trackedFiles(limit: Int) async throws -> [String] {
        let result = try await run(["ls-files", "-z"])
        var paths: [String] = []
        for path in result.stdout.split(separator: "\0") where paths.last != String(path) {
            paths.append(String(path))
            if paths.count == limit { break }
        }
        return paths
    }
}
