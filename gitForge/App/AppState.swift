import Foundation
import Observation
import AppKit

enum GitInstallationStatus: Sendable, Equatable {
    case checking
    case available
    case notFound
}

@Observable
@MainActor
final class AppState {
    var gitStatus: GitInstallationStatus = .checking
    var repositories: [Repository] = []
    var activeRepository: Repository?
    var activeViewModel: RepositoryViewModel?
    var presentedError: PresentedError?

    private let store = RepositoryStore()

    func bootstrap() async {
        async let gitCheck: Void = refreshGitInstallation()
        await store.load()
        repositories = await store.repositories
        _ = await gitCheck
    }

    func refreshGitInstallation() async {
        if gitStatus != .checking {
            gitStatus = .checking
        }
        let isAvailable = await GitCLI.isGitAvailable()
        gitStatus = isAvailable ? .available : .notFound
    }

    func openRepository(at url: URL) async throws {
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            throw RepositoryError.directoryNotFound(url)
        }
        guard await GitCLI.isGitRepository(at: url) else {
            throw RepositoryError.notAGitRepository(url)
        }
        repositories = await store.touch(url)
        let active = repositories.first { $0.url == url }
        activeRepository = active
        if let active, activeViewModel?.repository.url != active.url {
            activeViewModel = RepositoryViewModel(repository: active)
        }
    }

    func activate(_ repository: Repository) async {
        do {
            try await openRepository(at: repository.url)
        } catch {
            presentedError = PresentedError(error: error)
        }
    }

    func closeRepository() {
        activeRepository = nil
        activeViewModel = nil
    }

    func removeFromRecents(_ url: URL) async {
        repositories = await store.remove(url)
        if activeRepository?.url == url {
            activeRepository = nil
            activeViewModel = nil
        }
    }

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
            presentedError = PresentedError(error: error)
        }
    }
}

struct PresentedError: Identifiable, Sendable {
    let id = UUID()
    let title: String
    let message: String

    init(title: String = "Couldn’t open repository", message: String) {
        self.title = title
        self.message = message
    }

    init(error: Error, title: String = "Couldn’t open repository") {
        self.title = title
        self.message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
