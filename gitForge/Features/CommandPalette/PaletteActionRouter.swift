import Foundation

/// Maps a `PaletteAction` to its side-effect on `AppState` / the active
/// `RepositoryViewModel`. Owns the success/error toast emission so callers
/// (currently `ShellView`) don't reimplement remote-op error handling.
@MainActor
struct PaletteActionRouter {
    let appState: AppState

    func route(_ action: PaletteAction) {
        switch action {
        case .openRepo(let url):
            Task { try? await appState.openRepository(at: url) }
        case .selectSection(let section):
            appState.ui.workspaceSection = section
        case .fetch:
            runRemote(label: "Fetched") { vm in await vm.fetch() }
        case .pull:
            runRemote(label: "Pulled") { vm in await vm.pull() }
        case .push:
            runRemote(label: "Pushed") { vm in await vm.push() }
        case .stash:
            runStash()
        case .noop:
            break
        }
    }

    private func runStash() {
        Task {
            guard let vm = appState.catalog.activeViewModel else { return }
            switch await vm.stashAll() {
            case .success:
                appState.ui.activeToast = ToastMessage(message: "Stashed", kind: .ok)
            case .failure(let error):
                appState.ui.activeToast = ToastMessage(
                    message: error.userMessage,
                    kind: .error
                )
            }
        }
    }

    /// Runs a remote VM operation. Only emits the success toast — failures
    /// are surfaced by the global `remoteFailure` observer in `ShellView`,
    /// so menu / toolbar / palette entry points all share the same error UX.
    private func runRemote(label: String, _ block: @escaping (RepositoryViewModel) async -> Void) {
        Task {
            guard let vm = appState.catalog.activeViewModel else { return }
            vm.remoteFailure = nil
            await block(vm)
            if vm.remoteFailure == nil {
                appState.ui.activeToast = ToastMessage(message: label, kind: .ok)
            }
        }
    }
}
