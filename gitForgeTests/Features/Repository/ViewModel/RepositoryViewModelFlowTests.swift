import Foundation
import Testing
@testable import gitForge

/// End-to-end view-model flows against a real repository (audit A09): the
/// integration paths had only "bogus working dir" guard tests.
@Suite("RepositoryViewModel — real-git flows", .serialized)
@MainActor
struct RepositoryViewModelFlowTests {

    private func localRef(_ name: String, in vm: RepositoryViewModel) throws -> GitRef {
        try #require(vm.localBranches.first { $0.name == name })
    }

    @Test("Merge with conflicts routes to the resolver; abort returns to a clean tree")
    func mergeConflictThenAbort() async throws {
        let repo = try await GitTestRepo.make { repo in
            try repo.commit("base", files: ["f.txt": "base\n"])
            try repo.git("checkout", "-q", "-b", "other")
            try repo.commit("theirs", files: ["f.txt": "theirs\n"])
            try repo.git("checkout", "-q", "main")
            try repo.commit("ours", files: ["f.txt": "ours\n"])
        }
        defer { repo.remove() }
        let vm = RepositoryViewModel(repository: Repository(url: repo.url))
        await vm.loadRefs()

        let outcome = await vm.mergeBranch(try localRef("other", in: vm))
        #expect(outcome == .conflicts)
        #expect(vm.mergeState == .merging)
        #expect(vm.conflicts.files.map(\.path) == ["f.txt"])
        #expect(vm.conflicts.hunks.count == 1)

        await vm.abortMerge()
        #expect(vm.mergeState == .clean)
        #expect(vm.conflicts.files.isEmpty)
        #expect(repo.read("f.txt") == "ours\n")
    }

    @Test("Resolving every hunk then continuing completes the merge")
    func resolveAndContinue() async throws {
        let repo = try await GitTestRepo.make { repo in
            try repo.commit("base", files: ["f.txt": "base\n"])
            try repo.git("checkout", "-q", "-b", "other")
            try repo.commit("theirs", files: ["f.txt": "theirs\n"])
            try repo.git("checkout", "-q", "main")
            try repo.commit("ours", files: ["f.txt": "ours\n"])
        }
        defer { repo.remove() }
        let vm = RepositoryViewModel(repository: Repository(url: repo.url))
        await vm.loadRefs()
        _ = await vm.mergeBranch(try localRef("other", in: vm))

        let hunk = try #require(vm.conflicts.hunks.first)
        vm.conflicts.setPick(hunkId: hunk.id, pick: .theirs)
        await vm.resolveSelectedFile()
        #expect(vm.conflicts.files.allSatisfy { $0.resolved })

        await vm.continueMerge()
        #expect(vm.mergeState == .clean)
        #expect(repo.read("f.txt") == "theirs\n")
        #expect(try repo.git("log", "-1", "--format=%P").split(separator: " ").count == 2)
    }

    @Test("Create, list and delete a tag")
    func tagLifecycle() async throws {
        let repo = try await GitTestRepo.make { try $0.commit("init", files: ["a": "a\n"]) }
        defer { repo.remove() }
        let vm = RepositoryViewModel(repository: Repository(url: repo.url))

        guard case .success = await vm.createTag(name: "v1.0", message: "first") else {
            Issue.record("createTag failed"); return
        }
        let tag = try #require(vm.tags.first { $0.name == "v1.0" })
        guard case .success = await vm.deleteTag(tag) else {
            Issue.record("deleteTag failed"); return
        }
        #expect(vm.tags.isEmpty)
    }

    @Test("Checkout switches branch and is refused while another mutation runs")
    func checkoutAndBusyGuard() async throws {
        let repo = try await GitTestRepo.make { repo in
            try repo.commit("init", files: ["a": "a\n"])
            try repo.git("branch", "feature")
        }
        defer { repo.remove() }
        let vm = RepositoryViewModel(repository: Repository(url: repo.url))
        await vm.loadRefs()
        let feature = try localRef("feature", in: vm)

        vm.isMutating = true
        guard case .failure(let error) = await vm.checkoutBranch(feature) else {
            Issue.record("checkout should be refused while busy"); return
        }
        #expect(error as? GitError == .busy)
        #expect(vm.currentBranchName == "main")

        vm.isMutating = false
        guard case .success = await vm.checkoutBranch(feature) else {
            Issue.record("checkout failed"); return
        }
        #expect(vm.currentBranchName == "feature")
    }
}
