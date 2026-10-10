import Foundation
import Testing
@testable import gitForge

@Suite("RepositoryViewModel — reveal in History", .serialized)
@MainActor
struct RepositoryViewModelRevealTests {

    private static func makeVM() -> RepositoryViewModel {
        let url = URL(fileURLWithPath: "/var/empty/gitForge-tests-\(UUID().uuidString)")
        let vm = RepositoryViewModel(repository: Repository(url: url))
        vm.commits = ["aaa", "bbb", "ccc"].map {
            Commit(sha: $0, parentShas: [], authorName: "T", authorEmail: "t@example.com",
                   authorDate: .init(timeIntervalSince1970: 0), subject: $0)
        }
        vm.selectedCommitId = "aaa"
        return vm
    }

    @Test("A loaded branch tip becomes the selected commit")
    func revealsLoadedTip() {
        let vm = Self.makeVM()
        let ref = GitRef(name: "feature/x", kind: .localBranch, targetSha: "ccc", isHead: false)
        #expect(vm.revealInHistory(ref))
        #expect(vm.selectedCommitId == "ccc")
    }

    @Test("A tip outside the loaded history reports false and keeps the selection")
    func missingTip() {
        let vm = Self.makeVM()
        let ref = GitRef(name: "old", kind: .localBranch, targetSha: "zzz", isHead: false)
        #expect(!vm.revealInHistory(ref))
        #expect(vm.selectedCommitId == "aaa")
    }
}
