import Foundation

extension ReviewsStore {
    /// Selects `item` and asks its detail to open `action`'s panel or sheet
    /// once loaded: handed to its repo's detail store as soon as that has
    /// the pull request open (`forwardQuickAction`).
    func requestQuickAction(_ action: PullQuickAction, for item: InboxPull) {
        selectedID = item.id
        pendingQuickAction = PendingInboxQuickAction(itemID: item.id, action: action)
        forwardQuickAction()
    }

    /// Hands the pending quick action to the selection's detail store once
    /// that has its pull request open; until then it waits. It goes when
    /// the selection moved to another row meanwhile.
    func forwardQuickAction() {
        guard let pending = pendingQuickAction else { return }
        guard let item = selectedItem, item.id == pending.itemID else {
            pendingQuickAction = nil
            return
        }
        guard let store = detailStore(for: item.repo.id), store.selected?.number == item.pull.number else { return }
        pendingQuickAction = nil
        store.requestQuickAction(pending.action, on: item.pull)
    }
}
