import Foundation
import Testing
@testable import gitForge

@Suite("BranchValidator")
struct BranchValidatorTests {
    @Test("Accepts plain names")
    func accepts() {
        #expect(BranchValidator.isValidName("main"))
        #expect(BranchValidator.isValidName("feature/login"))
        #expect(BranchValidator.isValidName("release/2026.05"))
        #expect(BranchValidator.isValidName("bugfix-1234"))
    }

    @Test("Rejects empty / whitespace-only")
    func rejectsEmpty() {
        #expect(!BranchValidator.isValidName(""))
        #expect(!BranchValidator.isValidName("   "))
    }

    @Test("Rejects names with whitespace inside")
    func rejectsInternalWhitespace() {
        #expect(!BranchValidator.isValidName("my branch"))
    }

    @Test("Rejects leading dot, trailing slash, double-dot")
    func rejectsStructuralInvalid() {
        #expect(!BranchValidator.isValidName(".hidden"))
        #expect(!BranchValidator.isValidName("feature/"))
        #expect(!BranchValidator.isValidName("feature..login"))
    }

    @Test("Rejects names with reserved characters")
    func rejectsReservedChars() {
        for ch in ["~", "^", ":", "?", "*", "[", "\\"] {
            #expect(!BranchValidator.isValidName("foo\(ch)bar"), "should reject '\(ch)'")
        }
    }
}

@Suite("RepositoryViewModel — branch op guards", .serialized)
@MainActor
struct RepositoryViewModelBranchOpTests {

    private static func makeVM() -> RepositoryViewModel {
        // The guard tests below all return before touching `cli`, so a bogus
        // working directory is safe.
        let url = URL(fileURLWithPath: "/var/empty/gitForge-tests-\(UUID().uuidString)")
        return RepositoryViewModel(repository: Repository(url: url))
    }

    private static func tag(_ name: String) -> GitRef {
        GitRef(name: name, kind: .tag, targetSha: "deadbeef", isHead: false)
    }

    private static func localBranch(_ name: String) -> GitRef {
        GitRef(name: name, kind: .localBranch, targetSha: "deadbeef", isHead: false)
    }

    @Test("createBranch rejects an invalid name before hitting the CLI")
    func createBranchRejectsInvalidName() async {
        let vm = Self.makeVM()
        let result = await vm.createBranch(name: "bad name", startingAt: nil, checkout: false)
        guard case .failure(let error) = result else {
            Issue.record("Expected failure for invalid name")
            return
        }
        guard case BranchOpError.invalidName(let name) = error else {
            Issue.record("Expected BranchOpError.invalidName, got \(error)")
            return
        }
        #expect(name == "bad name")
    }

    @Test("renameBranch rejects an invalid new name")
    func renameBranchRejectsInvalidName() async {
        let vm = Self.makeVM()
        let result = await vm.renameBranch(from: "main", to: ".hidden")
        guard case .failure(let error) = result,
              case BranchOpError.invalidName = error else {
            Issue.record("Expected BranchOpError.invalidName")
            return
        }
    }

    @Test("moveBranch refuses non-local refs (tag / remote)")
    func moveBranchRefusesNonLocal() async {
        let vm = Self.makeVM()
        let result = await vm.moveBranch(Self.tag("v1.0.0"), to: "deadbeef")
        guard case .failure(let error) = result,
              case BranchOpError.notALocalBranch = error else {
            Issue.record("Expected BranchOpError.notALocalBranch")
            return
        }
    }

    @Test("moveBranch refuses the currently checked-out branch")
    func moveBranchRefusesCurrent() async {
        let vm = Self.makeVM()
        vm.currentBranchName = "main"
        let result = await vm.moveBranch(Self.localBranch("main"), to: "deadbeef")
        guard case .failure(let error) = result,
              case BranchOpError.cannotMoveCurrentBranch = error else {
            Issue.record("Expected BranchOpError.cannotMoveCurrentBranch")
            return
        }
    }

    @Test("BranchOpError surfaces a localized description for each case")
    func errorDescriptionsArePresent() {
        #expect(BranchOpError.invalidName("x").errorDescription?.isEmpty == false)
        #expect(BranchOpError.notALocalBranch.errorDescription?.isEmpty == false)
        #expect(BranchOpError.cannotMoveCurrentBranch.errorDescription?.isEmpty == false)
    }
}
