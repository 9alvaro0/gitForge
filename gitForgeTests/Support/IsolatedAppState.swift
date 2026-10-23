import Foundation
@testable import gitForge

extension AppState {
    /// An `AppState` whose recents, preferences, profiles, accounts and
    /// Reviews snapshot and settings live in temporary storage, never the
    /// user's.
    /// `reviewsSnapshots`: a store a test has filled.
    @MainActor
    static func isolated(reviewsSnapshots: ReviewsSnapshotStore? = nil) -> AppState {
        let dir = TemporaryDirectories.make("gitForge-app")
        let defaults = TestDefaults(prefix: "gitForge-app").defaults
        return AppState(catalog: RepositoryCatalog(store: RepositoryStore(directory: dir), defaults: defaults),
                        profiles: ProfileStore(defaults: defaults),
                        accounts: AccountStore(directory: dir, secrets: InMemoryAccountSecretStore()),
                        reviewsSnapshots: reviewsSnapshots ?? ReviewsSnapshotStore(directory: dir),
                        reviewsConfig: ReviewsConfigStore(directory: dir))
    }
}
