import Foundation

extension GitCLI {
    static func isGitRepository(at url: URL) async -> Bool {
        await resolveRepositoryRoot(at: url) != nil
    }

    /// Resolves to the worktree toplevel for `url`. Returns the toplevel URL
    /// when `url` is the root or a subdirectory of a repo, `nil` otherwise.
    /// Callers must use the returned URL — not the original — so subsequent
    /// operations operate on the real root instead of a subdirectory (path
    /// resolution for conflicts/untracked files assumes toplevel).
    static func resolveRepositoryRoot(at url: URL) async -> URL? {
        let path = url.path(percentEncoded: false)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return nil
        }
        let cli = GitCLI(workingDirectory: url)
        do {
            let result = try await cli.run(["rev-parse", "--show-toplevel"])
            let top = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !top.isEmpty else { return nil }
            return URL(fileURLWithPath: top).standardizedFileURL
        } catch {
            return nil
        }
    }

    /// Resolves the per-worktree git directory. In a regular repo this is
    /// `<worktree>/.git`. In a linked worktree (`git worktree add`), `.git` is
    /// a file containing `gitdir: <path>` pointing at
    /// `<main>/.git/worktrees/<name>` — the per-worktree gitdir where HEAD,
    /// MERGE_HEAD and friends actually live. Returns nil for paths that
    /// aren't a repository worktree at all.
    ///
    /// Pure filesystem read, no subprocess — safe to call from sync init paths
    /// (RepositoryWatcher) and hot probes (mergeState).
    static func resolveGitDirectory(in worktree: URL) -> URL? {
        let dotGit = worktree.appendingPathComponent(".git")
        let path = dotGit.path(percentEncoded: false)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir) else { return nil }
        if isDir.boolValue { return dotGit }
        // `.git` is a file → linked worktree marker. Parse the gitdir line.
        guard let content = try? String(contentsOf: dotGit, encoding: .utf8) else { return nil }
        let line = content.split(separator: "\n").first.map(String.init) ?? content
        guard line.hasPrefix("gitdir:") else { return nil }
        let raw = line.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
        if raw.isEmpty { return nil }
        if (raw as NSString).isAbsolutePath {
            return URL(fileURLWithPath: raw).standardizedFileURL
        }
        return worktree.appendingPathComponent(raw).standardizedFileURL
    }

    /// Resolves the shared git directory holding `refs/`, `objects/`, and
    /// `packed-refs`. In a main repo this matches `resolveGitDirectory`. In a
    /// linked worktree, the per-worktree gitdir contains a `commondir` file
    /// pointing back at the main `.git`. Falls back to the per-worktree
    /// gitdir if no `commondir` marker exists.
    static func resolveGitCommonDirectory(in worktree: URL) -> URL? {
        guard let gitDir = resolveGitDirectory(in: worktree) else { return nil }
        let commondirFile = gitDir.appendingPathComponent("commondir")
        guard FileManager.default.fileExists(atPath: commondirFile.path(percentEncoded: false)) else {
            return gitDir
        }
        guard let raw = (try? String(contentsOf: commondirFile, encoding: .utf8))?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            return gitDir
        }
        if (raw as NSString).isAbsolutePath {
            return URL(fileURLWithPath: raw).standardizedFileURL
        }
        return gitDir.appendingPathComponent(raw).standardizedFileURL
    }
}
