import Foundation
@testable import gitForge

extension AppState {
    /// An `AppState` whose recents, preferences, profiles and accounts live
    /// in temporary storage, never the user's.
    @MainActor
    static func isolated() -> AppState {
        let dir = TemporaryDirectories.make("gitForge-app")
        let defaults = TestDefaults(prefix: "gitForge-app").defaults
        return AppState(catalog: RepositoryCatalog(store: RepositoryStore(directory: dir), defaults: defaults),
                        profiles: ProfileStore(defaults: defaults),
                        accounts: AccountStore(directory: dir, secrets: InMemoryAccountSecretStore()))
    }
}
