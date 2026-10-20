import Foundation

nonisolated enum GitError: Error, Sendable, Equatable {
    case gitNotFound
    case invalidWorkingDirectory(URL)
    case launchFailed(String)
    case commandFailed(args: [String], exitCode: Int32, stderr: String)
    case busy
    /// Subprocess output exceeded the configured byte cap and was terminated
    /// to avoid runaway memory growth. Common trigger: `git log -p` or
    /// `diff` on a commit that renamed `node_modules` (or similar 100MB+
    /// blob deltas).
    case outputTooLarge(consumed: Int, cap: Int)
}

extension GitError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .gitNotFound:
            return String(localized: "Git executable not found. Install the Xcode Command Line Tools.")
        case .invalidWorkingDirectory(let url):
            let path = url.path(percentEncoded: false)
            return String(localized: "Working directory does not exist: \(path)")
        case .launchFailed(let reason):
            return String(localized: "Failed to launch git: \(reason)")
        case .commandFailed(let args, let exitCode, let stderr):
            if let message = Self.localChangesMessage(stderr: stderr) { return message }
            // Redact both sides — a `https://user:token@host` URL can land in
            // argv (clone) and in git's stderr ("unable to access ..."), and
            // this string ends up in user-visible alerts and shared logs.
            let command = GitCLI.redacted((["git"] + args).joined(separator: " "))
            let trimmed = GitCLI.redacted(stderr.trimmingCharacters(in: .whitespacesAndNewlines))
            let code = Int(exitCode)
            return String(localized: "`\(command)` exited with code \(code): \(trimmed)")
        case .busy:
            return String(localized: "Another operation is in progress.")
        case .outputTooLarge(let consumed, let cap):
            let consumedMB = consumed / 1_048_576
            let capMB = cap / 1_048_576
            return String(localized: "Output exceeded \(capMB) MB (read \(consumedMB) MB) and was terminated. The diff or log is too large for the UI — narrow the range or run from terminal.")
        }
    }
}

extension GitError {
    /// git refusing to run over uncommitted work (checkout, merge, pull,
    /// rebase), said plainly with the files in the way instead of the raw
    /// command and stderr. Keeps "would be overwritten" so callers that
    /// match on it still do.
    static func localChangesMessage(stderr: String) -> String? {
        if stderr.contains("cannot rebase: You have unstaged changes")
            || stderr.contains("cannot rebase: Your index contains uncommitted changes") {
            return String(localized: "You have uncommitted changes. Commit, stash or discard them before rebasing.")
        }
        guard stderr.contains("would be overwritten by") else { return nil }
        let files = stderr.split(separator: "\n")
            .filter { $0.hasPrefix("\t") }
            .map { $0.trimmingCharacters(in: .whitespaces) }
        let list = files.isEmpty ? "" : " (\(files.prefix(3).joined(separator: ", "))\(files.count > 3 ? ", …" : ""))"
        let untracked = stderr.contains("untracked working tree files")
        return untracked
            ? String(localized: "Untracked files would be overwritten\(list). Move or delete them, or commit them first.")
            : String(localized: "Your local changes would be overwritten\(list). Commit, stash or discard them first.")
    }
}
