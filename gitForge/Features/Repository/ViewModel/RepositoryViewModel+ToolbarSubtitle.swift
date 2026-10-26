import Foundation

extension RepositoryViewModel {
    /// Subtitle under the toolbar title (redesign spec §6.1). The shell owns
    /// it: a screen's own `.navigationSubtitle` loses to the shell's, so the
    /// per-section variants live here instead of in each screen.
    ///
    /// `pullsTab` is the tab Pull requests shows: Team and Mine are the inbox's
    /// and belong to no repository, so they show nothing under their title;
    /// Open and Closed are this repository's, and show where it lives.
    func toolbarSubtitle(for section: WorkspaceSection, pullsTab: PullsTab) -> String {
        switch section {
        case .pulls where pullsTab.half != nil:
            return ""
        case .pulls:
            guard let host = pullRequests.host else { return String(localized: "not connected") }
            return "\(host.slug) · \(host.provider.label.lowercased())"
        case .conflict where mergeState.isInProgress:
            return mergeStateSubtitle
        case .changes:
            // The staged / unstaged counts the old status bar showed.
            let branch = currentBranchName ?? String(localized: "Detached HEAD")
            guard !workingCopy.status.isClean else { return String(localized: "\(branch) · no changes") }
            let unstaged = workingCopy.status.unstagedFiles.count
            let staged = workingCopy.status.stagedFiles.count
            return String(localized: "\(branch) · \(unstaged) unstaged, \(staged) staged")
        default:
            return ShellStatus.subtitle(branch: currentBranchName, ahead: aheadCount, behind: behindCount)
        }
    }

    private var mergeStateSubtitle: String {
        let branch = currentBranchName ?? "HEAD"
        switch mergeState {
        case .merging:       return String(localized: "merging into \(branch)")
        case .rebasing:      return String(localized: "rebasing \(branch)")
        case .cherryPicking: return String(localized: "cherry-picking onto \(branch)")
        case .reverting:     return String(localized: "reverting on \(branch)")
        case .bisecting:     return String(localized: "bisecting")
        case .unmerged:      return String(localized: "applying stash on \(branch)")
        case .clean:         return ""
        }
    }
}
