import Foundation

extension RepositoryViewModel {
    /// Subtitle under the toolbar title (redesign spec §6.1). The shell owns
    /// it: a screen's own `.navigationSubtitle` loses to the shell's, so the
    /// per-section variants live here instead of in each screen.
    func toolbarSubtitle(for section: WorkspaceSection) -> String {
        switch section {
        case .pulls:
            guard let host = pullRequests.host else { return "not connected" }
            return "\(host.slug) · \(host.provider.label.lowercased())"
        case .conflict where mergeState.isInProgress:
            return mergeStateSubtitle
        case .changes:
            // The staged / unstaged counts the old status bar showed.
            let branch = currentBranchName ?? "Detached HEAD"
            guard !status.isClean else { return "\(branch) · no changes" }
            return "\(branch) · \(status.stagedFiles.count) staged, \(status.unstagedFiles.count) unstaged"
        default:
            return ShellStatus.subtitle(branch: currentBranchName, ahead: aheadCount, behind: behindCount)
        }
    }

    private var mergeStateSubtitle: String {
        let branch = currentBranchName ?? "HEAD"
        switch mergeState {
        case .merging:       return "merging into \(branch)"
        case .rebasing:      return "rebasing \(branch)"
        case .cherryPicking: return "cherry-picking onto \(branch)"
        case .reverting:     return "reverting on \(branch)"
        case .bisecting:     return "bisecting"
        case .unmerged:      return "applying stash on \(branch)"
        case .clean:         return ""
        }
    }
}
