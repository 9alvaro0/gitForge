import Foundation
import Testing
@testable import gitForge

@Suite("HookFailure")
struct HookFailureTests {

    private let commit = HookFailure.Operation.commit(pushAfterwards: false, confirmedAmendOfPublished: false)

    @Test("The hook named in the output wins, as a whole word")
    func hookNameFromOutput() {
        let installed = ["pre-commit", "prepare-commit-msg", "commit-msg"]
        #expect(HookFailure.hookName(in: "husky - pre-commit script failed (code 1)", installed: installed) == "pre-commit")
        #expect(HookFailure.hookName(in: "hook prepare-commit-msg exited 1", installed: installed) == "prepare-commit-msg")
        #expect(HookFailure.hookName(in: "commit-msg: subject too long", installed: installed) == "commit-msg")
        // Several installed and none named: unknown.
        #expect(HookFailure.hookName(in: "src/a.js:1 no-var", installed: installed) == nil)
    }

    @Test("With one installed hook and no name in the output, that's the one")
    func singleInstalledHook() {
        #expect(HookFailure.hookName(in: "3 tests failed", installed: ["pre-commit"]) == "pre-commit")
    }

    @Test("No installed hook, or a failure git reports itself, is not a hook failure")
    func notAHookFailure() {
        #expect(HookFailure(stderr: "boom", operation: commit, installedHooks: []) == nil)
        for stderr in [
            "fatal: Unable to create '/r/.git/index.lock': File exists.",
            "error: gpg failed to sign the data",
            "error: Committing is not possible because you have unmerged files.",
            "CONFLICT (content): Merge conflict in f.txt\nerror: could not apply abc123... x",
            "fatal: There is no merge in progress (MERGE_HEAD missing).",
        ] {
            #expect(HookFailure(stderr: stderr, operation: commit, installedHooks: ["pre-commit"]) == nil, "\(stderr)")
        }
    }

    @Test("Keeps the full output, trimmed")
    func keepsOutput() throws {
        let output = (1...200).map { "line \($0)" }.joined(separator: "\n")
        let failure = try #require(HookFailure(stderr: "\n" + output + "\n\n", operation: commit, installedHooks: ["pre-commit"]))
        #expect(failure.output == output)
        #expect(failure.hookName == "pre-commit")
    }

    @Test("Only a plain commit offers to skip hooks")
    func canSkipHooks() throws {
        let commitFailure = try #require(HookFailure(stderr: "no", operation: commit, installedHooks: ["pre-commit"]))
        #expect(commitFailure.canSkipHooks)
        for state in [MergeState.merging, .rebasing, .cherryPicking, .reverting] {
            let failure = try #require(HookFailure(stderr: "no", operation: .continueIntegration(state), installedHooks: ["pre-commit"]))
            #expect(!failure.canSkipHooks)
        }
    }

    @Test("Copy names the hook when known and never mentions the remote")
    func copy() {
        let named = HookFailure(operation: commit, hookName: "pre-commit", output: "")
        #expect(named.title == "The pre-commit hook failed")
        #expect(named.summary == "The pre-commit hook failed. Nothing was committed.")
        let unnamed = HookFailure(operation: .continueIntegration(.rebasing), hookName: nil, output: "")
        #expect(unnamed.title == "A Git hook failed")
        #expect(unnamed.message.contains("rebase"))
        for text in [named.title, named.message, named.summary, unnamed.title, unnamed.message] {
            #expect(!text.localizedCaseInsensitiveContains("remote"))
        }
    }
}
