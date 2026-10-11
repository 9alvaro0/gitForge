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
        chooser.answer(choice, for: shown!.id)
        #expect(await first == choice)
        #expect(await second == choice)
        #expect(chooser.request == nil)
    }

    @Test("A late answer for a sheet that's gone doesn't cancel the next one")
    func staleAnswer() async {
        let chooser = AccountChooser()
        async let first = chooser.choose(remote("/r/a"))
        async let second = chooser.choose(remote("/r/b"))
        await waitUntil { chooser.request != nil }
        let firstId = chooser.request!.id
        chooser.answer(.system, for: firstId)
        await waitUntil { chooser.request != nil && chooser.request?.id != firstId }
        chooser.answer(nil, for: firstId)
        #expect(chooser.request != nil)
        chooser.answer(.system, for: chooser.request!.id)
        #expect(await first == .system)
        #expect(await second == .system)
    }

    @Test("Cancel answers nil; the next remote's sheet comes after")
    func queue() async {
        let chooser = AccountChooser()
        async let first = chooser.choose(remote("/r/a"))
        async let second = chooser.choose(remote("/r/b"))
        await waitUntil { chooser.request != nil }
        let firstKey = chooser.request?.remote.repoPath
        chooser.answer(nil, for: chooser.request!.id)
        await waitUntil { chooser.request != nil && chooser.request?.remote.repoPath != firstKey }
        chooser.answer(.system, for: chooser.request!.id)
        let results = await [first, second]
        #expect(results.contains(nil))
        #expect(results.contains(.system))
    }

    @Test("A cancelled operation stops waiting: it gets nil and its sheet goes away")
    func cancelled() async {
        let chooser = AccountChooser()
        let waiting = Task { await chooser.choose(remote("/r/app")) }
        while chooser.request == nil { await Task.yield() }
        waiting.cancel()
        #expect(await waiting.value == nil)
        #expect(chooser.request == nil)
    }
}
