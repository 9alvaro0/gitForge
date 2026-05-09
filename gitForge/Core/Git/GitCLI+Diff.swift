import Foundation

extension GitCLI {
    func diffUnstaged(file: String) async throws -> String {
        try await run(["diff", contextArg, "--", file]).stdout
    }

    func diffStaged(file: String) async throws -> String {
        try await run(["diff", "--cached", contextArg, "--", file]).stdout
    }

    /// Resolves the user-configured diff context (`-U<n>`) at call time.
    /// Lives here so every diff helper picks up changes without threading
    /// the prefs store through `RepositoryViewModel` and the CLI layer.
    fileprivate var contextArg: String {
        "-U\(AppTheme.persistedDiffContextLines())"
    }
}
