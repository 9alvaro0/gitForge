import Foundation
import Testing
@testable import gitForge

@Suite("RepositoryViewModel — hunk and line staging", .serialized)
@MainActor
struct RepositoryViewModelHunkTests {

    private nonisolated static let base = (1...15).map(String.init).joined(separator: "\n") + "\n"
    /// Two hunks: line 2 → A, and line 13 → B, C.
    private nonisolated static let edited = base
        .replacingOccurrences(of: "\n2\n", with: "\nA\n")
        .replacingOccurrences(of: "\n13\n", with: "\nB\nC\n")

    private func makeRepo() async throws -> GitTestRepo {
        try await GitTestRepo.make { repo in
            try repo.commit("base", files: ["f.txt": Self.base])
            try repo.write(Self.edited, to: "f.txt")
        }
    }

    /// Opens f.txt's `side` and waits for its diff.
    private func open(_ side: WorkingCopySide, in vm: RepositoryViewModel) async throws -> WorkingCopyFile {
        await vm.workingCopy.refreshStatus()
        let file = try #require(vm.workingCopy.status.files.first { $0.path == "f.txt" })
        vm.workingCopy.select(file, side: side)
        await vm.workingCopy.loadWorkingCopyDiff(file: file)
        return file
    }

    @Test("Staging one hunk leaves the other unstaged")
    func stageHunk() async throws {
        let repo = try await makeRepo()
        defer { repo.remove() }
        let vm = RepositoryViewModel(repository: Repository(url: repo.url))
        let file = try await open(.unstaged, in: vm)
        let hunks = vm.workingCopy.workingCopyDiff
        #expect(hunks.count == 2)

        await vm.apply(.stage, hunk: hunks[1], in: file)

        let staged = try await repo.gitAsync("diff", "--cached", "--no-color")
        let unstaged = try await repo.gitAsync("diff", "--no-color")
        #expect(staged.contains("+B") && staged.contains("+C") && !staged.contains("+A"))
        #expect(unstaged.contains("+A") && !unstaged.contains("+B"))
        #expect(vm.commitError == nil)
        // The pane follows: the unstaged side now has one hunk.
        #expect(vm.workingCopy.workingCopyDiff.count == 1)
    }

    @Test("Staging picked lines stages only those")
    func stageLines() async throws {
        let repo = try await makeRepo()
        defer { repo.remove() }
        let vm = RepositoryViewModel(repository: Repository(url: repo.url))
        let file = try await open(.unstaged, in: vm)
        let hunk = vm.workingCopy.workingCopyDiff[1]
        let plusB = try #require(hunk.lines.first { $0.kind == .added && $0.content == "B" })

        await vm.apply(.stage, hunk: hunk, lineIds: [plusB.id], in: file)

        let staged = try await repo.gitAsync("diff", "--cached", "--no-color")
        #expect(staged.contains("+B"))
        #expect(!staged.contains("+C"))
        #expect(!staged.contains("-13"))
    }

    @Test("Unstaging picked lines and discarding a hunk")
    func unstageAndDiscard() async throws {
        let repo = try await makeRepo()
        defer { repo.remove() }
        try await repo.gitAsync("add", "f.txt")
        let vm = RepositoryViewModel(repository: Repository(url: repo.url))

        var file = try await open(.staged, in: vm)
        let stagedHunk = vm.workingCopy.workingCopyDiff[1]
        let plusC = try #require(stagedHunk.lines.first { $0.kind == .added && $0.content == "C" })
        await vm.apply(.unstage, hunk: stagedHunk, lineIds: [plusC.id], in: file)
        let staged = try await repo.gitAsync("diff", "--cached", "--no-color")
        #expect(staged.contains("+B") && !staged.contains("+C"))

        file = try await open(.unstaged, in: vm)
        let unstagedHunk = try #require(vm.workingCopy.workingCopyDiff.first)
        await vm.apply(.discard, hunk: unstagedHunk, in: file)
        #expect(!(repo.read("f.txt") ?? "").contains("C\n"))
        #expect(try await repo.gitAsync("diff", "--no-color").isEmpty)
    }

    @Test("No hunk actions for untracked files or with whitespace hidden")
    func availability() {
        let vm = RepositoryViewModel(repository: Repository(url: URL(fileURLWithPath: "/var/empty")))
        let modified = WorkingCopyFile(path: "a", stagedStatus: .unmodified, unstagedStatus: .modified, originalPath: nil)
        let untracked = WorkingCopyFile(path: "b", stagedStatus: .untracked, unstagedStatus: .untracked, originalPath: nil)
        let renamed = WorkingCopyFile(path: "c", stagedStatus: .renamed, unstagedStatus: .unmodified, originalPath: "old")
        #expect(vm.canApplyHunks(to: modified))
        #expect(!vm.canApplyHunks(to: untracked))
        #expect(!vm.canApplyHunks(to: renamed))
    }

    @Test("The pane shows the side picked, falling back when it's empty")
    func sides() {
        let store = RepositoryViewModel(repository: Repository(url: URL(fileURLWithPath: "/var/empty"))).workingCopy
        let both = WorkingCopyFile(path: "a", stagedStatus: .modified, unstagedStatus: .modified, originalPath: nil)
        let onlyStaged = WorkingCopyFile(path: "b", stagedStatus: .modified, unstagedStatus: .unmodified, originalPath: nil)
        #expect(store.diffSide(for: both) == .staged)
        store.select(both, side: .unstaged)
        #expect(store.diffSide(for: both) == .unstaged)
        #expect(store.diffSide(for: onlyStaged) == .staged)
    }
}
