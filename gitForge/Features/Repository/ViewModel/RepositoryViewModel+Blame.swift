import Foundation
import os

/// `git blame` integration on top of `RepositoryViewModel`.
extension RepositoryViewModel {
    func loadBlame(path: String) async {
        selectedBlamePath = path
        isLoadingBlame = true
        defer { isLoadingBlame = false }

        do {
            let porcelain = try await cli.blame(path: path)
            blameGroups = BlameParser.parse(porcelain)
            blameError = nil
        } catch {
            Self.logger.error("Blame failed for \(path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            blameError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            blameGroups = []
        }
    }
}
