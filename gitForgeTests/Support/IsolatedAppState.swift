import Foundation
@testable import gitForge

extension AppState {
    /// An `AppState` whose recents, preferences, profiles, accounts and
    /// Reviews snapshot and settings live in temporary storage, never the
    /// user's.
    /// `reviewsSnapshots`: a store a test has filled. `defaults`: a suite
    /// that outlives the state, to start another one on it as a relaunch.
    @MainActor
    static func isolated(reviewsSnapshots: ReviewsSnapshotStore? = nil, defaults: UserDefaults? = nil) -> AppState {
        let dir = TemporaryDirectories.make("gitForge-app")
        let defaults = defaults ?? TestDefaults(prefix: "gitForge-app").defaults
        return AppState(catalog: RepositoryCatalog(store: RepositoryStore(directory: dir), defaults: defaults),
                        profiles: ProfileStore(defaults: defaults),
                        accounts: AccountStore(directory: dir, secrets: InMemoryAccountSecretStore()),
                        reviewsSnapshots: reviewsSnapshots ?? ReviewsSnapshotStore(directory: dir),
                        reviewsConfig: ReviewsConfigStore(directory: dir),
                        defaults: defaults)
    }
}
