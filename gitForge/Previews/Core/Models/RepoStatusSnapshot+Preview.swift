import Foundation

extension RepoStatusSnapshot {
    /// "Active repo" snapshot — feature branch, dirty working copy, ahead of
    /// origin. Used to showcase the sidebar's pill stack and SidebarRepoRow.
    static let previewActive = RepoStatusSnapshot(
        branch: "feat/commit-graph", dirty: 3, ahead: 7, behind: 1
    )

    /// "Background repo" snapshot — clean main, no divergence. Pairs with
    /// `previewActive` to show the dim, unselected variant of the row.
    static let previewClean = RepoStatusSnapshot(
        branch: "main", dirty: 0, ahead: 0, behind: 0
    )

    /// "Never loaded" snapshot — placeholder pill with no branch yet.
    static let previewLoading = RepoStatusSnapshot.empty

    /// Convenience for previews that need a `(Repository) -> RepoStatusSnapshot`
    /// closure (e.g. `Sidebar`). Marks `active` as the dirty/ahead repo and
    /// every other repo as clean — mirrors the real wiring at runtime.
    static func previewStatusFor(active: Repository?) -> (Repository) -> RepoStatusSnapshot {
        { repo in repo.id == active?.id ? .previewActive : .previewClean }
    }
}
