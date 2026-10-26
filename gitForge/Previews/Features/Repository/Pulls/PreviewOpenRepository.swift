import Foundation

/// A repository open in gitForge in the previews, as Pull requests gets it:
/// its own list and local actions (`pulls`) and, for the inbox, its clone and
/// that same store (`active`, `ReviewsStore.preview(_:open:tab:)`).
@MainActor
struct PreviewOpenRepository {
    let pulls: PullsRepository
    let active: ActiveRepositoryPulls

    /// The clone of the repo at `path` on `instance`, reading the preview
    /// hosts (`PreviewReviewsWorld.repositoryStore`).
    init(_ path: String, on instance: HostingInstance = PreviewReviewsWorld.gitLab, connected: Bool = true) {
        let store = PreviewReviewsWorld.repositoryStore(path, on: instance, connected: connected)
        pulls = PullsRepository(store: store, localActions: .preview)
        active = ActiveRepositoryPulls(localURL: PreviewReviewsWorld.cloneURL(of: path), store: store)
    }

    /// payments-app, the clone the populated inboxes follow: its group is the
    /// first of Team and Mine, and its pull requests open with its local actions.
    static var paymentsApp: PreviewOpenRepository { PreviewOpenRepository(PreviewReviewsWorld.paymentsApp) }

    /// oss/lib on github.com, which nobody follows: Team shows it first all
    /// the same, as a group of its own.
    static var ossLib: PreviewOpenRepository {
        PreviewOpenRepository(PreviewReviewsWorld.ossLib, on: PreviewReviewsWorld.gitHub)
    }
}
