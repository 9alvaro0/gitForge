import Foundation
import Testing
@testable import gitForge

@Suite("AccountChooser", .serialized)
@MainActor
struct AccountChooserTests {
    private func remote(_ repo: String, _ name: String = "origin") -> AmbiguousRemote {
        AmbiguousRemote(repoPath: repo, remoteName: name, host: "github.com", ownerRepo: "org/app", candidates: [])
    }

    @Test("Two operations asking for the same remote share one sheet and one answer")
    func sharedAnswer() async {
        let chooser = AccountChooser()
        let choice = RepoAccountChoice.account(UUID())
        async let first = chooser.choose(remote("/r/a"))
        async let second = chooser.choose(remote("/r/a"))
        await waitUntil { chooser.request != nil }
        let shown = chooser.request
        try? await Task.sleep(for: .milliseconds(20))
        #expect(chooser.request == shown)
        chooser.answer(choice)
        #expect(await first == choice)
        #expect(await second == choice)
        #expect(chooser.request == nil)
    }

    @Test("Cancel answers nil; the next remote's sheet comes after")
    func queue() async {
        let chooser = AccountChooser()
        async let first = chooser.choose(remote("/r/a"))
        async let second = chooser.choose(remote("/r/b"))
        await waitUntil { chooser.request != nil }
        let firstKey = chooser.request?.remote.repoPath
        chooser.answer(nil)
        await waitUntil { chooser.request != nil && chooser.request?.remote.repoPath != firstKey }
        chooser.answer(.system)
        let results = await [first, second]
        #expect(results.contains(nil))
        #expect(results.contains(.system))
    }
}
