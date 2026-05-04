import Foundation
import Observation

enum GitInstallationStatus: Sendable, Equatable {
    case checking
    case available
    case notFound
}

@Observable
@MainActor
final class AppState {
    var gitStatus: GitInstallationStatus = .checking

    func refreshGitInstallation() async {
        if gitStatus != .checking {
            gitStatus = .checking
        }
        let isAvailable = await GitCLI.isGitAvailable()
        gitStatus = isAvailable ? .available : .notFound
    }
}
