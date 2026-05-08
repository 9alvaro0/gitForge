import Foundation
import SwiftUI

@MainActor
extension AppState {
    static var preview: AppState {
        let state = AppState()
        state.gitEnvironment.gitStatus = .available
        state.catalog.repositories = Repository.previewSamples
        return state
    }

    static var previewWithActive: AppState {
        let state = preview
        let repo = Repository.previewSamples.first!
        state.catalog.activeRepository = repo
        state.catalog.activeViewModel = RepositoryViewModel.preview
        return state
    }

    static var previewMissingGit: AppState {
        let state = AppState()
        state.gitEnvironment.gitStatus = .notFound
        return state
    }
}

@MainActor
extension View {
    /// Injects `AppState` plus its four sub-stores so previews of features
    /// that depend on `WorkspaceUI`, `RepositoryCatalog`, … find them in the
    /// environment without each preview having to wire all five by hand.
    func previewAppState(_ state: AppState) -> some View {
        self
            .environment(state)
            .environment(state.catalog)
            .environment(state.gitEnvironment)
            .environment(state.clone)
            .environment(state.ui)
    }
}
