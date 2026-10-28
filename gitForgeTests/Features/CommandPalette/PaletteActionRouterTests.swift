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

    // MARK: Settings

    @Test("A pane opens Settings on it, and Back goes to where Settings was opened from")
    func openSettingsPane() {
        let app = AppState.isolated()
        app.ui.workspaceSection = .history

        PaletteActionRouter(appState: app).route(.openSettings(.accounts))

        #expect(app.ui.workspaceSection == .settings)
        #expect(app.ui.settingsPane == .accounts)
        #expect(app.ui.sectionBeforeSettings == .history)
    }

    @Test("Settings without a pane opens on the last one")
    func openSettingsLast() {
        let app = AppState.isolated()
        app.ui.settingsPane = .git

        PaletteActionRouter(appState: app).route(.openSettings(nil))

        #expect(app.ui.workspaceSection == .settings)
        #expect(app.ui.settingsPane == .git)
    }

    @Test("A section pick of Settings, should one still arrive, opens it on the last pane")
    func legacySelectSettings() {
        let app = AppState.isolated()
        app.ui.workspaceSection = .changes
        app.ui.settingsPane = .appearance

        PaletteActionRouter(appState: app).route(.selectSection(.settings))

        #expect(app.ui.workspaceSection == .settings)
        #expect(app.ui.settingsPane == .appearance)
        #expect(app.ui.sectionBeforeSettings == .changes)
    }

    @Test("New Profile… opens Identities and asks it for a new profile")
    func newProfile() {
        let app = AppState.isolated()

        PaletteActionRouter(appState: app).route(.newProfile)

        #expect(app.ui.workspaceSection == .settings)
        #expect(app.ui.settingsPane == .identities)
        #expect(app.ui.newProfileRequest != nil)
        #expect(app.ui.followRepositoryRequest == nil)
    }

    @Test("Follow Repository… opens Pull requests and asks it to follow one")
    func followRepository() {
        let app = AppState.isolated()

        PaletteActionRouter(appState: app).route(.followRepository)

        #expect(app.ui.workspaceSection == .settings)
        #expect(app.ui.settingsPane == .pullRequests)
        #expect(app.ui.followRepositoryRequest != nil)
        #expect(app.ui.newProfileRequest == nil)
    }

    @Test("Connect account… opens the sheet on no instance in particular, replacing no account")
    func connectNewAccount() {
        let app = AppState.isolated()

        PaletteActionRouter(appState: app).route(.connectNewAccount)

        #expect(app.ui.connectAccountRequest != nil)
        #expect(app.ui.connectAccountRequest?.instanceId == nil)
        #expect(app.ui.connectAccountRequest?.replacing == nil)
    }

    @Test("Picking a repository while Settings is up leaves Settings at once, even if it's the one already open")
    func openRepoLeavesSettings() {
        let app = AppState.isolated()
        app.ui.workspaceSection = .changes
        app.ui.openSettings(.git)
        #expect(app.ui.workspaceSection == .settings)

        PaletteActionRouter(appState: app).route(.openRepo(URL(fileURLWithPath: "/var/empty/gitForge-tests-\(UUID().uuidString)")))

        // No suspension point since `route`: the open hasn't finished.
        #expect(app.ui.workspaceSection == .changes)
        #expect(app.ui.sectionBeforeSettings == nil)
    }

    @Test("Picking a repository outside Settings doesn't touch the section until the open says it switched")
    func openRepoOutsideSettings() {
        let app = AppState.isolated()
        app.ui.workspaceSection = .changes

        PaletteActionRouter(appState: app).route(.openRepo(URL(fileURLWithPath: "/var/empty/gitForge-tests-\(UUID().uuidString)")))

        #expect(app.ui.workspaceSection == .changes)
    }

    // MARK: Pull requests and links

    /// An app whose inbox loaded team/app, not cloned, with the user's !4 and
    /// lucia's !5.
    private static func appWithInbox() throws -> (app: AppState, repo: ReviewRepo, pullID: InboxPull.ID) {
        let instance = HostingInstance(kind: .gitlab, host: "gitlab.example.test")
        let accountId = UUID()
        let repo = ReviewRepo(host: try #require(RemoteHost.make(fullName: "team/app", on: instance)),
                              accountId: accountId, sources: [], lastActivity: nil,
                              cloneURL: "https://gitlab.example.test/team/app.git", localURL: nil)
        let pull = PullRequest(id: "iid:4", number: 4, title: "MR 4", state: .open, authorLogin: "marta",
                               authorAvatarURL: nil, sourceBranch: "feature/4", targetBranch: "main", webURL: nil,
                               createdAt: nil, updatedAt: nil)
        let teammate = PullRequest(id: "iid:5", number: 5, title: "MR 5", state: .open, authorLogin: "lucia",
                                   authorAvatarURL: nil, sourceBranch: "feature/5", targetBranch: "main", webURL: nil,
                                   createdAt: nil, updatedAt: nil)
        let snapshots = ReviewsSnapshotStore(directory: TemporaryDirectories.make("gitForge-router-reviews"))
        snapshots.save(ReviewsSnapshot(version: ReviewsSnapshot.currentVersion,
                                       savedAt: Date(timeIntervalSince1970: 1_790_000_000),
                                       repos: [repo], pulls: [repo.id: [pull, teammate]], memberships: [:],
                                       logins: [accountId: "marta"]))
        let app = AppState.isolated(reviewsSnapshots: snapshots)
        app.reviews.loadSnapshot()
        return (app, repo, InboxPull.id(repoKey: repo.id, number: 4))
    }

    @Test("A pull request opens Pull requests with it selected, on the half that shows it")
    func openPull() throws {
        let (app, _, id) = try Self.appWithInbox()
        #expect(app.reviews.filter == .team)

        PaletteActionRouter(appState: app).route(.openPull(id: id))

        #expect(app.ui.workspaceSection == .pulls)
        #expect(app.reviews.selectedID == id)
        // The user's own: Mine shows it.
        #expect(app.reviews.filter == .mine)
        #expect(app.reviews.selectedItem?.id == id)
    }

    @Test("A pull request picked while the repository's Closed list shows opens the inbox, on the half that shows it")
    func openPullFromRepositoryTab() throws {
        let (app, repo, _) = try Self.appWithInbox()
        app.reviews.tab = .closed
        let id = InboxPull.id(repoKey: repo.id, number: 5)

        PaletteActionRouter(appState: app).route(.openPull(id: id))

        #expect(app.ui.workspaceSection == .pulls)
        #expect(app.reviews.selectedID == id)
        // lucia's: Team shows it, not the Closed list the section was on.
        #expect(app.reviews.tab == .team)
        #expect(app.reviews.selectedItem?.id == id)
    }

    @Test("A repo that isn't cloned opens Pull requests narrowed to it")
    func showReviews() throws {
        let (app, repo, _) = try Self.appWithInbox()

        PaletteActionRouter(appState: app).route(.showReviews(repoKey: repo.id))

        #expect(app.ui.workspaceSection == .pulls)
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

    @Test("A pasted link goes to Pull requests at once, before the inbox has read it")
    func linkGoesToReviewsAtOnce() throws {
        let app = AppState.isolated()
        let link = try #require(PullRequestLink.parse("https://github.com/octo/lib/pull/7", instances: app.accounts.instances))

        PaletteActionRouter(appState: app).route(.openPullLink(link))

        // No suspension point since `route`: the read hasn't started yet.
        #expect(app.ui.workspaceSection == .pulls)
    }

    @Test("A link on an instance with no account goes to Pull requests and asks to connect one")
    func linkWithoutAccounts() async throws {
        let app = AppState.isolated()
        let link = try #require(PullRequestLink.parse("https://github.com/octo/lib/pull/7", instances: app.accounts.instances))

        await PaletteActionRouter(appState: app).openLink(link)

        #expect(app.ui.workspaceSection == .pulls)
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

    // MARK: Search all

    private static func found(_ repo: ReviewRepo, instanceId: UUID = UUID()) -> FoundRepo {
        FoundRepo(host: repo.host, instanceId: instanceId, cloneURL: repo.cloneURL)
    }

    @Test("Connecting an account from a search row opens the sheet on that instance")
    func connectAccount() {
        let app = AppState.isolated()
        let id = UUID()
        PaletteActionRouter(appState: app).route(.connectAccount(instanceId: id))
        #expect(app.ui.connectAccountRequest?.instanceId == id)
    }

    @Test("A found repo goes to Pull requests at once, before the inbox has read it")
    func foundRepoGoesToReviewsAtOnce() throws {
        let (app, repo, _) = try Self.appWithInbox()
        app.ui.workspaceSection = .history

        PaletteActionRouter(appState: app).route(.openFoundRepo(Self.found(repo)))

        #expect(app.ui.workspaceSection == .pulls)
    }

    @Test("A found repo that's followed opens Pull requests narrowed to it")
    func openFoundRepoFollowed() async throws {
        let (app, repo, _) = try Self.appWithInbox()
        app.ui.workspaceSection = .history

        await PaletteActionRouter(appState: app).openFoundRepo(Self.found(repo))

        #expect(app.ui.workspaceSection == .pulls)
        #expect(app.reviews.filteredRepo?.id == repo.id)
        #expect(app.ui.connectAccountRequest == nil)
        #expect(app.ui.activeToast == nil)
    }

    @Test("A found repo no account can read asks to connect one on its instance")
    func openFoundRepoWithoutAccounts() async throws {
        let app = AppState.isolated()
        let instance = HostingInstance.gitHubDotCom
        let host = try #require(RemoteHost.make(fullName: "octo/lib", on: instance))

        await PaletteActionRouter(appState: app).openFoundRepo(
            FoundRepo(host: host, instanceId: instance.id, cloneURL: "https://github.com/octo/lib.git"))

        #expect(app.ui.workspaceSection == .pulls)
        #expect(app.ui.connectAccountRequest?.instanceId == instance.id)
        #expect(app.ui.activeToast == nil)
    }

    @Test("Closing the connect sheet with no pending link changes nothing")
    func retryWithoutPendingLink() async {
        let app = AppState.isolated()
        app.ui.workspaceSection = .history

        await PaletteActionRouter(appState: app).connectSheetClosed()

        #expect(app.ui.workspaceSection == .history)
        #expect(app.ui.connectAccountRequest == nil)
        #expect(app.ui.activeToast == nil)
    }

    @Test("A pending link whose instance still has no account is dropped, changing nothing")
    func retryStillWithoutAccount() async throws {
        let app = AppState.isolated()
        let link = try #require(PullRequestLink.parse("https://github.com/octo/lib/pull/7", instances: app.accounts.instances))
        let router = PaletteActionRouter(appState: app)
        await router.openLink(link)
        #expect(app.reviews.pendingLink == link)
        // The sheet closed without connecting anything.
        app.ui.connectAccountRequest = nil
        app.ui.workspaceSection = .history

        await router.connectSheetClosed()

        #expect(app.ui.workspaceSection == .history)
        #expect(app.ui.connectAccountRequest == nil)
        #expect(app.reviews.pendingLink == nil)
    }

    @Test("Closing the connect sheet turns a search that asked for an account back into the row that searches")
    func connectSheetClosedForgetsConnectSearches() async throws {
        let app = AppState.isolated()
        let instance = HostingInstance.gitLabDotCom
        let expired = HostingAccount(instanceId: instance.id, login: "marta", method: .personalToken,
                                     status: .needsAttention(.expired))
        try app.accounts.addAccount(expired, secret: AccountSecret(accessToken: "test-pat-value"))
        await app.reviews.searchHost(instance.id, query: "retry")
        #expect(app.reviews.hostSearches[instance.id]?.phase == .connectAccount)

        await PaletteActionRouter(appState: app).connectSheetClosed()

        #expect(app.reviews.hostSearches[instance.id] == nil)
        let rows = CommandPaletteBuilder.searchItems(for: "retry", instances: app.reviews.searchInstances,
                                                     searches: app.reviews.hostSearches, followed: [])
        #expect(rows.map(\.label) == ["Search all of gitlab.com"])
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
