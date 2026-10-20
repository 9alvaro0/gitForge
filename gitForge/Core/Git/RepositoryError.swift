import Foundation

nonisolated enum RepositoryError: Error, Sendable, Equatable, LocalizedError {
    case notAGitRepository(URL)
    case directoryNotFound(URL)

    var errorDescription: String? {
        switch self {
        case .notAGitRepository(let url):
            let name = url.lastPathComponent
            return String(localized: "“\(name)” is not a Git repository.")
        case .directoryNotFound(let url):
            let path = url.path(percentEncoded: false)
            return String(localized: "Folder not found: \(path)")
        }
    }
}
