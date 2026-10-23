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

    /// An app whose inbox loaded team/app, not cloned, with the user's !4.
    private static func appWithInbox() throws -> (app: AppState, repo: ReviewRepo, pullID: InboxPull.ID) {
        let instance = HostingInstance(kind: .gitlab, host: "gitlab.example.test")
        let accountId = UUID()
        let repo = ReviewRepo(host: try #require(RemoteHost.make(fullName: "team/app", on: instance)),
                              accountId: accountId, sources: [], lastActivity: nil,
                              cloneURL: "https://gitlab.example.test/team/app.git", localURL: nil)
        let pull = PullRequest(id: "iid:4", number: 4, title: "MR 4", state: .open, authorLogin: "marta",
                               authorAvatarURL: nil, sourceBranch: "feature/4", targetBranch: "main", webURL: nil,
                               createdAt: nil, updatedAt: nil)
        let snapshots = ReviewsSnapshotStore(directory: TemporaryDirectories.make("gitForge-router-reviews"))
        snapshots.save(ReviewsSnapshot(version: ReviewsSnapshot.currentVersion,
                                       savedAt: Date(timeIntervalSince1970: 1_790_000_000),
                                       repos: [repo], pulls: [repo.id: [pull]], memberships: [:],
                                       logins: [accountId: "marta"]))
        let app = AppState.isolated(reviewsSnapshots: snapshots)
        app.reviews.loadSnapshot()
        return (app, repo, InboxPull.id(repoKey: repo.id, number: 4))
    }

    @Test("A pull request opens Reviews with it selected, on the half that shows it")
    func openPull() throws {
        let (app, _, id) = try Self.appWithInbox()
        #expect(app.reviews.filter == .team)

        PaletteActionRouter(appState: app).route(.openPull(id: id))

        #expect(app.ui.workspaceSection == .reviews)
        #expect(app.reviews.selectedID == id)
        // The user's own: Mine shows it.
        #expect(app.reviews.filter == .mine)
        #expect(app.reviews.selectedItem?.id == id)
    }

    @Test("A repo that isn't cloned opens Reviews narrowed to it")
    func showReviews() throws {
        let (app, repo, _) = try Self.appWithInbox()

        PaletteActionRouter(appState: app).route(.showReviews(repoKey: repo.id))

        #expect(app.ui.workspaceSection == .reviews)
        #expect(app.reviews.filteredRepo?.id == repo.id)
        #expect(app.reviews.groups.map(\.repo.id) == [repo.id])
    }

    @Test("Adding an instance from a link opens the sheet on that host, as the kind its URL said")
    func addInstance() {
        let app = AppState.isolated()
        PaletteActionRouter(appState: app).route(.addInstance(kind: .gitlab, host: "code.example.test"))
        #expect(app.ui.addInstanceRequest?.kind == .gitlab)
        #expect(app.ui.addInstanceRequest?.url == "https://code.example.test")
    }

    @Test("A pasted link goes to Reviews at once, before the inbox has read it")
    func linkGoesToReviewsAtOnce() throws {
        let app = AppState.isolated()
        let link = try #require(PullRequestLink.parse("https://github.com/octo/lib/pull/7", instances: app.accounts.instances))

        PaletteActionRouter(appState: app).route(.openPullLink(link))

        // No suspension point since `route`: the read hasn't started yet.
        #expect(app.ui.workspaceSection == .reviews)
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

    @Test("Adding an instance and opening a link may show a sheet, so ⌘↵ still closes the palette for them")
    func presentsUI() throws {
        let link = try #require(PullRequestLink.parse("https://github.com/octo/lib/pull/7",
                                                      instances: HostingInstance.builtIns))
        #expect(PaletteAction.addInstance(kind: .github, host: "ghe.example.test").presentsUI)
        // Its outcome can be the connect sheet.
        #expect(PaletteAction.openPullLink(link).presentsUI)
        #expect(!PaletteAction.openPull(id: "x#1").presentsUI)
        #expect(!PaletteAction.showReviews(repoKey: "x").presentsUI)
    }
}
