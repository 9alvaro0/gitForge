import Foundation
import Testing
@testable import gitForge

@Suite("RepositoryViewModel — operations error handling", .serialized)
@MainActor
struct RepositoryViewModelOperationsTests {

    private static func makeVM() -> RepositoryViewModel {
        // Bogus working dir → every cli call throws `GitError.invalidWorkingDirectory`
        // on the first guard, so we land deterministically in the catch path
        // without needing a fake CLI.
        let url = URL(fileURLWithPath: "/var/empty/gitForge-tests-\(UUID().uuidString)")
        return RepositoryViewModel(repository: Repository(url: url))
    }

    private static func commit(_ sha: String, parents: [String] = []) -> Commit {
        Commit(
            sha: sha,
            parentShas: parents,
            authorName: "Test",
            authorEmail: "t@example.com",
            authorDate: .init(timeIntervalSince1970: 0),
            subject: "subject"
        )
    }

    @Test("cherryPick clears stale commitError and surfaces a fresh failure message")
    func cherryPickClearsStaleError() async {
        let vm = Self.makeVM()
        vm.commitError = "stale error from a previous op"
        let outcome = await vm.cherryPick(Self.commit("deadbeef"))
        guard case .failed(let message) = outcome else {
            Issue.record("Expected .failed for a bogus working directory, got \(outcome)")
            return
        }
        #expect(!message.isEmpty)
        #expect(message != "stale error from a previous op")
        #expect(vm.commitError == message)
    }

    @Test("revert clears stale commitError and surfaces a fresh failure message")
    func revertClearsStaleError() async {
        let vm = Self.makeVM()
        vm.commitError = "stale"
        let outcome = await vm.revert(Self.commit("deadbeef"))
        guard case .failed(let message) = outcome else {
            Issue.record("Expected .failed, got \(outcome)")
            return
        }
        #expect(message != "stale")
        #expect(vm.commitError == message)
    }

    @Test("reset clears stale commitError and surfaces a fresh failure message")
    func resetClearsStaleError() async {
        let vm = Self.makeVM()
        vm.commitError = "stale"
        let outcome = await vm.reset(to: "deadbeef", mode: .soft)
        guard case .failed(let message) = outcome else {
            Issue.record("Expected .failed, got \(outcome)")
            return
        }
        #expect(message != "stale")
        #expect(vm.commitError == message)
    }
}

@Suite("GitCLI.ResetMode")
struct ResetModeTests {

    @Test("flag mirrors the rawValue with a leading double-dash")
    func flagFormat() {
        #expect(GitCLI.ResetMode.soft.flag == "--soft")
        #expect(GitCLI.ResetMode.mixed.flag == "--mixed")
        #expect(GitCLI.ResetMode.hard.flag == "--hard")
    }

    @Test("each mode has a non-empty user-facing label")
    func labelsArePresent() {
        for mode in GitCLI.ResetMode.allCases {
            #expect(!mode.label.isEmpty)
        }
    }
}
