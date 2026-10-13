import Foundation

extension GitCLI {
    func diffUnstaged(file: String) async throws -> String {
        try await run(["diff"] + Self.diffOutputFlags + GitPreferences.diffWhitespaceArgs
                      + [contextArg, "--", file]).stdout
    }

    /// A conflicted file against HEAD: plain `git diff` gives a combined
    /// (`diff --cc`) diff the parser doesn't read, so the pane said "No
    /// changes" over a file full of conflict markers.
    func diffAgainstHead(file: String) async throws -> String {
        try await run(["diff", "HEAD"] + Self.diffOutputFlags + GitPreferences.diffWhitespaceArgs
                      + [contextArg, "--", file]).stdout
    }

    /// `originalPath`: a staged rename's old path. Both have to be in the
    /// pathspec for git to pair them; with the new one alone the whole file
    /// read as added.
    func diffStaged(file: String, originalPath: String? = nil) async throws -> String {
        try await run(["diff", "--cached", "-M"] + Self.diffOutputFlags + GitPreferences.diffWhitespaceArgs
                      + [contextArg, "--", file] + (originalPath.map { [$0] } ?? [])).stdout
    }

    /// The lines of `path` at `revision` (`""` reads the index), to expand a
    /// diff's hidden context. `nil` when the file isn't there (deleted on
    /// that side) or is too big to be worth loading.
    func fileLines(revision: String, path: String) async -> [String]? {
        guard let result = try? await run(["show", "\(revision):\(path)"]),
              result.stdout.utf8.count <= DiffGaps.maxFileBytes else { return nil }
        return DiffGaps.splitLines(result.stdout)
    }

    /// Resolves the user-configured diff context (`-U<n>`) at call time.
    /// Lives here so every diff helper picks up changes without threading
    /// the prefs store through `RepositoryViewModel` and the CLI layer.
    fileprivate var contextArg: String {
        "-U\(GitPreferences.diffContextLines)"
    }
}
