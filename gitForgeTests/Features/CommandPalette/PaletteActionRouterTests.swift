import Foundation
import Testing
@testable import gitForge

@Suite("PaletteActionRouter", .serialized)
@MainActor
struct PaletteActionRouterTests {
    @Test("Clone repository… opens the clone sheet")
    func clone() {
        let app = AppState.isolated()
        PaletteActionRouter(appState: app).route(.cloneRepository)
        #expect(app.ui.cloneRequest != nil)
    }

    private static func appWithRepo() -> AppState {
        let app = AppState.isolated()
        let url = URL(fileURLWithPath: "/var/empty/gitForge-tests-\(UUID().uuidString)")
        app.catalog.activeViewModel = RepositoryViewModel(repository: Repository(url: url))
        return app
    }

    @Test("A commit opens History with that commit selected")
    func revealCommit() {
        let app = Self.appWithRepo()
        PaletteActionRouter(appState: app).route(.revealCommit(sha: "abc123"))
        #expect(app.ui.workspaceSection == .history)
        #expect(app.catalog.activeViewModel?.history.selectedCommitId == "abc123")
    }

    @Test("A branch outside the loaded history opens History and says so")
    func revealBranchNotLoaded() {
        let app = Self.appWithRepo()
        let ref = GitRef(name: "old", kind: .localBranch, targetSha: "dead", isHead: false)
        PaletteActionRouter(appState: app).route(.revealBranch(ref))
        #expect(app.ui.workspaceSection == .history)
        #expect(app.ui.activeToast?.kind == .warn)
    }

    @Test("A file opens Changes with its diff, on the side that has changes")
    func revealFile() {
        let app = Self.appWithRepo()
        let vm = try! #require(app.catalog.activeViewModel)
        vm.workingCopy.status = WorkingCopyStatus(files: [
            WorkingCopyFile(path: "a.txt", stagedStatus: .modified, unstagedStatus: .unmodified, originalPath: nil),
        ])
        PaletteActionRouter(appState: app).route(.revealFile(path: "a.txt"))
        #expect(app.ui.workspaceSection == .changes)
        #expect(vm.workingCopy.selectedWorkingCopyFile?.path == "a.txt")
    }

    // MARK: Pull requests and links

    @Test("A pull request opens Reviews")
    func openPull() {
        let app = AppState.isolated()
        PaletteActionRouter(appState: app).route(.openPull(id: "gitlab.example.test/team/app#4"))
        #expect(app.ui.workspaceSection == .reviews)
    }

    @Test("A repo that isn't cloned opens Reviews")
    func showReviews() {
        let app = AppState.isolated()
        PaletteActionRouter(appState: app).route(.showReviews(repoKey: "gitlab.example.test/team/app"))
        #expect(app.ui.workspaceSection == .reviews)
    }

    @Test("Adding an instance from a link opens the sheet on that host, as the kind its URL said")
    func addInstance() {
        let app = AppState.isolated()
        PaletteActionRouter(appState: app).route(.addInstance(kind: .gitlab, host: "code.example.test"))
        #expect(app.ui.addInstanceRequest?.kind == .gitlab)
        #expect(app.ui.addInstanceRequest?.url == "https://code.example.test")
    }

    @Test("A link on an instance with no account goes to Reviews and asks to connect one")
    func linkWithoutAccounts() async throws {
        let app = AppState.isolated()
        let link = try #require(PullRequestLink.parse("https://github.com/octo/lib/pull/7", instances: app.accounts.instances))

        await PaletteActionRouter(appState: app).openLink(link)

        #expect(app.ui.workspaceSection == .reviews)
        #expect(app.ui.connectAccountRequest?.instanceId == HostingInstance.gitHubDotCom.id)
        #expect(app.ui.activeToast == nil)
    }

    @Test("A link that couldn't be opened says why")
    func failedLink() {
        let app = AppState.isolated()
        PaletteActionRouter(appState: app).present(.failed("octo/lib #7 — Not found"))
        #expect(app.ui.activeToast?.kind == .error)
        #expect(app.ui.activeToast?.message == "octo/lib #7 — Not found")
        #expect(app.ui.connectAccountRequest == nil)
    }

    @Test("A link that opened leaves nothing more to show")
    func openedLink() {
        let app = AppState.isolated()
        PaletteActionRouter(appState: app).present(.opened("github.com/octo/lib#7"))
        #expect(app.ui.activeToast == nil)
        #expect(app.ui.connectAccountRequest == nil)
    }

    @Test("Only adding an instance opens a sheet, so ⌘↵ still closes the palette for it")
    func presentsUI() {
        #expect(PaletteAction.addInstance(kind: .github, host: "ghe.example.test").presentsUI)
        #expect(!PaletteAction.openPull(id: "x#1").presentsUI)
        #expect(!PaletteAction.showReviews(repoKey: "x").presentsUI)
    }
}
