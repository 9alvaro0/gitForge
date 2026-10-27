import Foundation
import Testing
@testable import gitForge

/// A row's Approve or Merge in Team and Mine: it selects the row and waits
/// for the repo's detail store to have the pull request open, then goes to it.
@Suite("Reviews store, quick actions")
@MainActor
struct ReviewsStoreQuickActionTests {
    /// team/app with !1 and !2 by `octo`, read.
    private static func loaded() async -> ReviewsStore {
        let harness = ReviewsHarness.twoRepos()
        harness.provider.state {
            $0.lists["team/app"] = [ReviewsHarness.pr(1, by: "octo", updated: 100),
                                    ReviewsHarness.pr(2, by: "octo", updated: 200)]
        }
        let store = harness.makeStore()
        await store.refresh(force: true)
        return store
    }

    private static func row(_ store: ReviewsStore, _ number: Int) throws -> InboxPull {
        try #require(store.groups.flatMap(\.pulls).first { $0.pull.number == number })
    }

    @Test("It selects the row and waits until the detail store has it open, then hands it over")
    func forwardedOnceOpen() async throws {
        let store = await Self.loaded()
        let item = try Self.row(store, 1)
        store.requestQuickAction(.merge, for: item)
        #expect(store.selectedID == item.id)
        #expect(store.pendingQuickAction == PendingInboxQuickAction(itemID: item.id, action: .merge))

        await store.open(item)
        store.forwardQuickAction()
        #expect(store.pendingQuickAction == nil)
        let detail = try #require(store.detailStore(for: item.repo.id))
        #expect(detail.pendingQuickAction == PendingPullQuickAction(pullNumber: 1, action: .merge))
    }

    @Test("On the row already open it goes over at once")
    func forwardedAtOnce() async throws {
        let store = await Self.loaded()
        let item = try Self.row(store, 2)
        store.selectedID = item.id
        await store.open(item)
        store.requestQuickAction(.approve, for: item)
        #expect(store.pendingQuickAction == nil)
        #expect(store.detailStore(for: item.repo.id)?.pendingQuickAction
            == PendingPullQuickAction(pullNumber: 2, action: .approve))
    }

    @Test("Another row selected meanwhile: it goes, and the detail store gets nothing")
    func selectionMoved() async throws {
        let store = await Self.loaded()
        let first = try Self.row(store, 1)
        let second = try Self.row(store, 2)
        store.requestQuickAction(.merge, for: first)
        store.selectedID = second.id
        await store.open(second)
        store.forwardQuickAction()
        #expect(store.pendingQuickAction == nil)
        #expect(store.detailStore(for: second.repo.id)?.pendingQuickAction == nil)
    }
}
