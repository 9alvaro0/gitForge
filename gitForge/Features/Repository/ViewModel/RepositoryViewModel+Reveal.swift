import Foundation

extension RepositoryViewModel {
    /// Selects `ref`'s tip in History. Returns `false`, leaving the selection
    /// alone, when that commit isn't in the loaded log.
    @discardableResult
    func revealInHistory(_ ref: GitRef) -> Bool {
        guard commits.contains(where: { $0.sha == ref.targetSha }) else { return false }
        selectedCommitId = ref.targetSha
        return true
    }
}
