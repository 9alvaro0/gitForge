import Foundation

nonisolated enum RepositoryError: Error, Sendable, Equatable, LocalizedError {
    case notAGitRepository(URL)
    case directoryNotFound(URL)

    var errorDescription: String? {
        switch self {
        case .notAGitRepository(let url):
            return "“\(url.lastPathComponent)” is not a Git repository."
        case .directoryNotFound(let url):
            return "Folder not found: \(url.path(percentEncoded: false))"
        }
    }
}
