import Foundation
import Testing
@testable import gitForge

@Suite("CommitActionsSection.resetConfirmMessage")
@MainActor
struct CommitActionsResetMessageTests {

    private let sha = "abc1234"

    @Test("nil mode returns an empty string (no resetMode armed)")
    func nilReturnsEmpty() {
        #expect(CommitActionsSection.resetConfirmMessage(for: nil, shortSha: sha).isEmpty)
    }

    @Test("Soft message mentions the target sha and 'staged changes'")
    func softMentionsStaged() {
        let message = CommitActionsSection.resetConfirmMessage(for: .soft, shortSha: sha)
        #expect(message.contains(sha))
        #expect(message.contains("staged"))
        // Soft must NOT hint at destruction.
        #expect(message.contains("DISCARDS") == false)
    }

    @Test("Mixed message mentions 'unstaged changes' and preserves working tree")
    func mixedMentionsUnstagedAndWorktree() {
        let message = CommitActionsSection.resetConfirmMessage(for: .mixed, shortSha: sha)
        #expect(message.contains("unstaged"))
        #expect(message.contains("Working tree is untouched"))
    }

    @Test("Hard message warns about discarding commits AND uncommitted changes")
    func hardWarnsExplicitly() {
        let message = CommitActionsSection.resetConfirmMessage(for: .hard, shortSha: sha)
        #expect(message.contains(sha))
        #expect(message.contains("DISCARDS"))
        #expect(message.contains("uncommitted"))
        #expect(message.contains("reflog"))
        #expect(message.contains("cannot be undone"))
    }

    @Test("All non-nil modes embed the sha")
    func allModesEmbedSha() {
        for mode in GitCLI.ResetMode.allCases {
            let message = CommitActionsSection.resetConfirmMessage(for: mode, shortSha: sha)
            #expect(message.contains(sha), "mode \(mode) should embed sha")
        }
    }
}
