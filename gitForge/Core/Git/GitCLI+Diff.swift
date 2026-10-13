import Foundation

extension GitCLI {
    func diffUnstaged(file: String) async throws -> String {
        try await run(["diff"] + Self.diffOutputFlags + GitPreferences.diffWhitespaceArgs
                      + [contextArg, "--", file]).stdout
    }

    func diffStaged(file: String) async throws -> String {
        try await run(["diff", "--cached"] + Self.diffOutputFlags + GitPreferences.diffWhitespaceArgs
                      + [contextArg, "--", file]).stdout
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
