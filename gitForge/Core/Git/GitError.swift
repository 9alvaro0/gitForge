import Foundation

nonisolated enum GitError: Error, Sendable, Equatable {
    case gitNotFound
    case invalidWorkingDirectory(URL)
    case launchFailed(String)
    case commandFailed(args: [String], exitCode: Int32, stderr: String)
    case busy
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
            let command = (["git"] + args).joined(separator: " ")
            let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return "`\(command)` exited with code \(exitCode): \(trimmed)"
        case .busy:
            return "Another remote operation is in progress."
        }
    }
}
