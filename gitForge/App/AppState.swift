import Foundation
import Observation
import AppKit

/// Coordinator over the four sub-stores. Holds only flows that legitimately
/// touch more than one store (open/clone, bootstrap), plus the AppKit panels
/// that pick a directory or repo. Single-domain operations live on the
/// matching sub-store and views read those directly via `@Environment`.
@Observable
@MainActor
final class AppState {
    let catalog: RepositoryCatalog
    let gitEnvironment: GitEnvironment
    let clone: CloneController
    let ui: WorkspaceUI
    let profiles: ProfileStore

    init(
        catalog: RepositoryCatalog? = nil,
        gitEnvironment: GitEnvironment? = nil,
        clone: CloneController? = nil,
        ui: WorkspaceUI? = nil,
        profiles: ProfileStore? = nil
    ) {
        // Default-arg expressions evaluate at the call site's isolation, but
        // `RepositoryCatalog`/etc. are `@MainActor`. Defer construction to the
        // body so the init's own `@MainActor` context covers the calls.
        self.catalog = catalog ?? RepositoryCatalog()
        self.gitEnvironment = gitEnvironment ?? GitEnvironment()
        self.clone = clone ?? CloneController()
        self.ui = ui ?? WorkspaceUI()
        self.profiles = profiles ?? ProfileStore()
    }

    // MARK: - Bootstrap

    /// Spins up the app: probes git, reads global config, loads recents,
    /// reopens the last active repo, and starts the status poller.
    func bootstrap() async {
        async let gitCheck: Void = gitEnvironment.refreshGitInstallation()
        async let configRead: Void = gitEnvironment.refreshGlobalConfig()
        await catalog.load()
        _ = await gitCheck
        _ = await configRead

        // After the global config has landed, materialise it as a profile if
        // none exists yet. Onboarding handles the empty-config first-run case
        // by creating a profile alongside the global write; this seed covers
        // existing users who already had a `~/.gitconfig` before the app
        // learned about profiles.
        profiles.seedFromGlobalIfEmpty(gitEnvironment.globalConfig)

        if await catalog.restoreLastActive() {
            ui.workspaceSection = .history
        }
        catalog.startStatusPolling()
    }

    // MARK: - Repository open / activate (cross-cutting: catalog + ui)

    /// Opens a repo and resets the workspace section to History when it's a
    /// switch from a different one. Throws on validation errors so callers
    /// can decide whether to surface them (the `activate` shortcut does).
    func openRepository(at url: URL) async throws {
        let isSwitching = try await catalog.open(at: url)
        if isSwitching {
            ui.workspaceSection = .history
        }
    }

    /// Convenience for the sidebar / Open Recent: opens the repo and surfaces
    /// any failure as a global alert.
    func activate(_ repository: Repository) async {
        do {
            try await openRepository(at: repository.url)
        } catch {
            ui.presentedError = PresentedError(error: error)
        }
    }

    // MARK: - Clone (cross-cutting: clone + catalog + ui)

    /// Clones `url` into `path` (with optional `~` expansion) and opens the
    /// resulting repository when it finishes. Fire-and-forget — observe
    /// `clone.cloneState` for progress; call `clone.cancel()` to abort.
    func startClone(url: String, path: String, branch: String?) {
        clone.start { [weak self] in
            await self?.runClone(url: url, path: path, branch: branch)
        }
    }

    private func runClone(url: String, path: String, branch: String?) async {
        let trimmedUrl = url.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUrl.isEmpty, !trimmedPath.isEmpty else {
            ui.presentedError = PresentedError(title: "Clone failed", message: "Source URL and local path are required.")
            return
        }
        let expanded = (trimmedPath as NSString).expandingTildeInPath
        let destination = URL(fileURLWithPath: expanded)
        if FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) {
            ui.presentedError = PresentedError(title: "Clone failed", message: "Destination already exists: \(expanded)")
            return
        }

        clone.cloneState = .running(stage: "Connecting…", percent: 0)
        defer { clone.cloneState = .idle }

        do {
            try await GitCLI.clone(
                url: trimmedUrl,
                destination: destination,
                branch: branch,
                onProgress: { [weak self] progress in
                    Task { @MainActor [weak self] in
                        self?.clone.cloneState = .running(stage: progress.stage, percent: progress.percent)
                    }
                }
            )
            try await openRepository(at: destination)
            ui.workspaceSection = .history
            ui.activeToast = ToastMessage(message: "Cloned \(destination.lastPathComponent)", kind: .ok)
        } catch is CancellationError {
            Self.cleanupPartialClone(at: destination)
            ui.activeToast = ToastMessage(message: "Clone cancelled", kind: .info)
        } catch {
            Self.cleanupPartialClone(at: destination)
            ui.presentedError = PresentedError(error: error, title: "Clone failed")
        }
    }

    /// Only deletes if the directory contains a `.git` entry — guards against
    /// a TOCTOU where the user materialised the path between the pre-flight
    /// existence check and git starting. Uses Trash so a misfire is recoverable.
    static func cleanupPartialClone(at destination: URL) {
        let fm = FileManager.default
        let gitDir = destination.appendingPathComponent(".git").path(percentEncoded: false)
        guard fm.fileExists(atPath: gitDir) else { return }
        _ = try? fm.trashItem(at: destination, resultingItemURL: nil)
    }

    // MARK: - AppKit pickers (UI helpers that result in opening a repo)

    /// Opens an `NSOpenPanel` and returns the chosen directory's path. Used
    /// by the Clone view to pick a parent directory.
    func pickDirectoryPath(prompt: String = "Choose") async -> String? {
        let panel = NSOpenPanel()
        panel.title = prompt
        panel.prompt = prompt
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return url.path(percentEncoded: false)
    }

    /// Open Repository menu / sidebar entry. Picks a folder, opens it as a
    /// repo, and surfaces any failure.
    func presentOpenRepositoryPanel() async {
        let panel = NSOpenPanel()
        panel.title = "Open Repository"
        panel.prompt = "Open"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try await openRepository(at: url)
        } catch {
            ui.presentedError = PresentedError(error: error)
        }
    }
}
