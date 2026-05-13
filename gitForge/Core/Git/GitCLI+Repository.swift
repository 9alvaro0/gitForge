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
}
