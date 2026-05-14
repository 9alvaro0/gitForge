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
            return "Git executable not found. Install the Xcode Command Line Tools."
        case .invalidWorkingDirectory(let url):
            return "Working directory does not exist: \(url.path(percentEncoded: false))"
        case .launchFailed(let reason):
            return "Failed to launch git: \(reason)"
        case .commandFailed(let args, let exitCode, let stderr):
            // Redact both sides — a `https://user:token@host` URL can land in
            // argv (clone) and in git's stderr ("unable to access ..."), and
            // this string ends up in user-visible alerts and shared logs.
            let command = GitCLI.redacted((["git"] + args).joined(separator: " "))
            let trimmed = GitCLI.redacted(stderr.trimmingCharacters(in: .whitespacesAndNewlines))
            return "`\(command)` exited with code \(exitCode): \(trimmed)"
        case .busy:
            return "Another remote operation is in progress."
        case .outputTooLarge(let consumed, let cap):
            let consumedMB = consumed / 1_048_576
            let capMB = cap / 1_048_576
            return "Output exceeded \(capMB) MB (read \(consumedMB) MB) and was terminated. The diff or log is too large for the UI — narrow the range or run from terminal."
        }
    }
}
