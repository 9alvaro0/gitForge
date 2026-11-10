import Foundation

extension GitCLI {
    /// Which of `names` are installed as executable hooks. Asks git for each
    /// path (`rev-parse --git-path hooks/<name>`), so `core.hooksPath` and
    /// linked worktrees are honoured. git skips a hook file that isn't
    /// executable, and so does this.
    func installedHooks(_ names: [String]) async -> [String] {
        guard !names.isEmpty else { return [] }
        let args = ["rev-parse"] + names.flatMap { ["--git-path", "hooks/\($0)"] }
        guard let result = try? await run(args) else { return [] }
        let paths = result.stdout.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard paths.count >= names.count else { return [] }
        return zip(names, paths).compactMap { name, path in
            let url = path.hasPrefix("/")
                ? URL(fileURLWithPath: path)
                : workingDirectory.appendingPathComponent(path)
            return FileManager.default.isExecutableFile(atPath: url.path(percentEncoded: false)) ? name : nil
        }
    }
}
