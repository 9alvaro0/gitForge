import Foundation
import Testing
@testable import gitForge

@Suite("RepositoryViewModel — renameBranch", .serialized)
@MainActor
struct RepositoryViewModelRenameBranchTests {

    private static func makeVM() async throws -> (GitTestRepo, RepositoryViewModel) {
        let repo = try await GitTestRepo.make {
            try $0.commit("first", files: ["a.txt": "1"])
            try $0.git("branch", "feat/old")
        }
        let vm = RepositoryViewModel(repository: Repository(url: repo.url))
        await vm.loadRefs()
        return (repo, vm)
    }

    @Test("Renaming refreshes the branch list")
    func refreshesRefs() async throws {
        let (repo, vm) = try await Self.makeVM()
        defer { repo.remove() }

        _ = try await vm.renameBranch(from: "feat/old", to: "feat/new").get()

        #expect(vm.localBranches.map(\.name).sorted() == ["feat/new", "main"])
    }

    @Test("Renaming the checked-out branch updates the current branch name")
    func updatesCurrentBranch() async throws {
        let (repo, vm) = try await Self.makeVM()
        defer { repo.remove() }

        _ = try await vm.renameBranch(from: "main", to: "trunk").get()

        #expect(vm.currentBranchName == "trunk")
    }

    @Test("A name another branch has fails and leaves the refs as they were")
    func existingNameFails() async throws {
        let (repo, vm) = try await Self.makeVM()
        defer { repo.remove() }

        let result = await vm.renameBranch(from: "feat/old", to: "main")

        guard case .failure(let error) = result,
              case BranchOpError.nameTaken("main") = error else {
            Issue.record("Expected BranchOpError.nameTaken(\"main\"), got \(result)")
            return
        }
        #expect(vm.localBranches.map(\.name).sorted() == ["feat/old", "main"])
    }
}

@Suite("Rename branch sheet")
struct BranchRenameSheetTests {
    @Test("Confirm is off for an empty name or the current one, on for a new one")
    func confirmDisabled() {
        #expect(BranchRenameSheetModifier.confirmDisabled(draft: "", original: "main"))
        #expect(BranchRenameSheetModifier.confirmDisabled(draft: "   ", original: "main"))
        #expect(BranchRenameSheetModifier.confirmDisabled(draft: "main", original: "main"))
        #expect(BranchRenameSheetModifier.confirmDisabled(draft: " main ", original: "main"))
        #expect(!BranchRenameSheetModifier.confirmDisabled(draft: "trunk", original: "main"))
    }
}
