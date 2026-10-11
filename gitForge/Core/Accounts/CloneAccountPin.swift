import Foundation

/// Clone › "My repos" clones with the account the list was browsed with
/// (spec §7.4). The choice is recorded for the destination's `origin`
/// before git runs, so the resolver's manual step signs the clone with it;
/// it's dropped if the clone fails, and follows the repo if it opens under
/// another path (symlinks resolved by git).
@MainActor
struct CloneAccountPin {
    private let store: AccountStore
    private let accountId: UUID
    private(set) var repoPath: String

    /// `nil` when there's no account to pin (or it no longer exists).
    static func pin(_ accountId: UUID?, destination: URL, in store: AccountStore) -> CloneAccountPin? {
        guard let accountId, store.accounts.contains(where: { $0.id == accountId }) else { return nil }
        let pin = CloneAccountPin(store: store, accountId: accountId, repoPath: destination.path(percentEncoded: false))
        store.setChoice(.account(accountId), repoPath: pin.repoPath, remoteName: "origin")
        return pin
    }

    /// The clone failed or was cancelled: forget the choice, unless
    /// something else has replaced it meanwhile.
    func undo() {
        guard store.choice(repoPath: repoPath, remoteName: "origin") == .account(accountId) else { return }
        store.setChoice(nil, repoPath: repoPath, remoteName: "origin")
    }

    /// The clone opened as `openedPath`.
    mutating func move(to openedPath: String) {
        guard openedPath != repoPath else { return }
        undo()
        store.setChoice(.account(accountId), repoPath: openedPath, remoteName: "origin")
        repoPath = openedPath
    }
}
