import Foundation

/// Maps a `PaletteAction` to its side-effect on `AppState` / the active
/// `RepositoryViewModel`. Fetch / pull / push toasts come from the view
/// model's outcome events (see `ShellView`); the rest toast here.
@MainActor
struct PaletteActionRouter {
    let appState: AppState

    func route(_ action: PaletteAction) {
        switch action {
        case .openRepo(let url):
            Task {
                do {
                    try await appState.openRepository(at: url)
                } catch {
                    // A recent that was moved or deleted must say so, not
                    // silently do nothing.
                    appState.ui.presentedError = PresentedError(error: error)
                }
            }
        case .openRepository:
            Task { await appState.presentOpenRepositoryPanel() }
        case .cloneRepository:
            appState.ui.requestClone()
        case .selectSection(let section):
            appState.ui.workspaceSection = section
        case .revealCommit(let sha):
            appState.ui.workspaceSection = .history
            appState.catalog.activeViewModel?.history.selectedCommitId = sha
        case .revealBranch(let ref):
            appState.ui.workspaceSection = .history
            if let vm = appState.catalog.activeViewModel, !vm.history.revealInHistory(ref) {
                let name = ref.name
                appState.ui.activeToast = ToastMessage(
                    message: String(localized: "“\(name)” isn’t in the loaded history"),
                    kind: .warn
                )
            }
        case .revealFile(let path):
            appState.ui.workspaceSection = .changes
            if let workingCopy = appState.catalog.activeViewModel?.workingCopy,
               let file = workingCopy.status.files.first(where: { $0.path == path }) {
                workingCopy.select(file, side: file.isUnstaged ? .unstaged : .staged)
            }
        case .openPull(let id):
            appState.ui.workspaceSection = .reviews
            appState.reviews.reveal(id)
        case .showReviews(let repoKey):
            appState.ui.workspaceSection = .reviews
            appState.reviews.showRepo(repoKey)
        case .openPullLink(let link):
            // Reviews before the read starts: its detail column says what's
            // being opened (Ruling 11, "at once").
            appState.ui.workspaceSection = .reviews
            Task { await openLink(link) }
        case .addInstance(let kind, let host):
            appState.ui.addInstanceRequest = AddInstanceRequest(kind: kind, url: "https://\(host)")
        case .fetch:
            runRemote { vm in await vm.fetch() }
        case .pull:
            runRemote { vm in await vm.pull() }
        case .push:
            runRemote { vm in await vm.push() }
        case .stash:
            runStash()
        case .searchHost(let instanceId, let query):
            // The palette stays open: the row turns into what the search finds.
            Task { await appState.reviews.searchHost(instanceId, query: query) }
        case .openFoundRepo(let repo):
            appState.ui.workspaceSection = .reviews
            Task { await openFoundRepo(repo) }
        case .connectAccount(let instanceId):
            appState.ui.connectAccountRequest = ConnectAccountRequest(instanceId: instanceId)
        case .noop:
            break
        }
    }

    /// A pasted pull request link (R2 Ruling 11): Reviews at once, where the
    /// detail column says it's being opened, and then what the inbox made of
    /// it. The outcome is acted on even when a newer link overtook this one.
    func openLink(_ link: PullRequestLink) async {
        appState.ui.workspaceSection = .reviews
        present(await appState.reviews.openLink(link))
    }

    /// A repo found by searching a host (R3 Ruling 13): Reviews at once,
    /// narrowed to it once the inbox has it, and what keeps it from opening
    /// told as for a link: the connect sheet or an error toast.
    func openFoundRepo(_ repo: FoundRepo) async {
        appState.ui.workspaceSection = .reviews
        switch await appState.reviews.openFoundRepo(repo) {
        case .shown:
            break
        case .connectAccount(let instanceId):
            present(.connectAccount(instanceId: instanceId))
        case .failed(let message):
            present(.failed(message))
        }
    }

    /// The sheet to connect an account closed, whatever opened it: the host
    /// searches that asked for an account go back to the row that searches,
    /// and the link that waited for one is opened again (R3 Ruling 14):
    /// Reviews and its outcome when the inbox tried it; nothing when there
    /// was none or its instance still has no account that signs.
    func connectSheetClosed() async {
        appState.reviews.forgetConnectSearches()
        guard let outcome = await appState.reviews.retryPendingLink() else { return }
        appState.ui.workspaceSection = .reviews
        present(outcome)
    }

    /// What a link's outcome asks of the app: nothing for a pull request that
    /// opened (the inbox selected it), the connect sheet for an instance with
    /// no account that can read it, an error toast for the rest.
    func present(_ outcome: LinkOpenOutcome) {
        switch outcome {
        case .opened:
            break
        case .connectAccount(let instanceId):
            appState.ui.connectAccountRequest = ConnectAccountRequest(instanceId: instanceId)
        case .failed(let message):
            appState.ui.activeToast = ToastMessage(message: message, kind: .error)
        }
    }

    private func runStash() {
        Task {
            guard let vm = appState.catalog.activeViewModel else { return }
            switch await vm.stashAll() {
            case .success:
                appState.ui.activeToast = ToastMessage(message: String(localized: "Stashed"), kind: .ok)
            case .failure(let error):
                appState.ui.activeToast = ToastMessage(
                    message: error.userMessage,
                    kind: .error
                )
            }
        }
    }

    /// Runs a remote VM operation. Success and failure toasts come from the
    /// view model's `operationSuccess` / `remoteFailure`, which `ShellView`
    /// observes, so menu / toolbar / palette entry points share the same UX.
    private func runRemote(_ block: @escaping (RepositoryViewModel) async -> Bool) {
        Task {
            guard let vm = appState.catalog.activeViewModel else { return }
            _ = await block(vm)
        }
    }
}
