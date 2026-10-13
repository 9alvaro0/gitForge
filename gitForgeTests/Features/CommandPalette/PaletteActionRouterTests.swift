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
}
