import Foundation
import Testing
@testable import gitForge

@Suite("BranchDropDialogs.mergeRebaseMessage")
@MainActor
struct BranchDropDialogsMessageTests {

    private func ref(_ name: String, kind: GitRef.Kind = .localBranch) -> GitRef {
        GitRef(name: name, kind: kind, targetSha: "0000000", isHead: false)
    }

    @Test("Nil request renders as empty string (dialog dismissed mid-render)")
    func nilReturnsEmpty() {
        #expect(BranchDropDialogs.mergeRebaseMessage(for: nil).isEmpty)
    }

    @Test("Distinguishes Merge vs Rebase explicitly so users know which is which")
    func mentionsBothPaths() {
        let req = MergeRebaseRequest(source: ref("feature/x"), target: ref("main"))
        let message = BranchDropDialogs.mergeRebaseMessage(for: req)
        #expect(message.contains("Merge:"))
        #expect(message.contains("Rebase:"))
    }

    @Test("Rebase branch is flagged as history-rewriting + force-push hint")
    func warnsAboutRebaseRewrite() {
        let req = MergeRebaseRequest(source: ref("feature/x"), target: ref("main"))
        let message = BranchDropDialogs.mergeRebaseMessage(for: req)
        // The whole point of this fix — the user must see "rewrites" and
        // "force push" before they pick Rebase.
        #expect(message.contains("rewrites"))
        #expect(message.contains("force push"))
    }

    @Test("Merge branch describes it as a new merge commit, history preserved")
    func describesMergeAsPreserving() {
        let req = MergeRebaseRequest(source: ref("feature/x"), target: ref("main"))
        let message = BranchDropDialogs.mergeRebaseMessage(for: req)
        #expect(message.contains("merge commit"))
        #expect(message.contains("History is preserved"))
    }

    @Test("Branch display names appear in the body so the user knows which way it goes")
    func includesBothBranchNames() {
        let req = MergeRebaseRequest(source: ref("feature/x"), target: ref("main"))
        let message = BranchDropDialogs.mergeRebaseMessage(for: req)
        #expect(message.contains("feature/x"))
        #expect(message.contains("main"))
    }
}
