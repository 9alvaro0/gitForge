import Foundation

/// Clone › "My repos" clones with the account the list was browsed with
/// (spec §7.4). The choice is recorded for the destination's `origin`
/// before git runs, so the resolver's manual step signs the clone with it;
/// whatever choice the path had before comes back if the clone fails, and
/// the pin follows the clone to its git root
/// (symlinks resolved), the path the repo is opened and signed under.
@MainActor
struct CloneAccountPin {
    private let store: AccountStore
    private let accountId: UUID
    private(set) var repoPath: String
    /// The path's choice before the pin (e.g. left by a deleted repo).
    private var previous: RepoAccountChoice?

    /// `nil` when there's no account to pin (or it no longer exists).
    static func pin(_ accountId: UUID?, destination: URL, in store: AccountStore) -> CloneAccountPin? {
        guard let accountId, store.accounts.contains(where: { $0.id == accountId }) else { return nil }
        let path = destination.path(percentEncoded: false)
        let pin = CloneAccountPin(store: store, accountId: accountId, repoPath: path,
                                  previous: store.choice(repoPath: path, remoteName: "origin"))
        store.setChoice(.account(accountId), repoPath: path, remoteName: "origin")
        return pin
    }

    /// The clone failed or was cancelled: put back the path's earlier
    /// choice, unless something else has replaced the pin meanwhile.
    func undo() {
        guard store.choice(repoPath: repoPath, remoteName: "origin") == .account(accountId) else { return }
        store.setChoice(previous, repoPath: repoPath, remoteName: "origin")
    }

    /// The clone finished: re-key the choice to its git root as the catalog
    /// will open it (symlinks resolved), whichever repo is active meanwhile.
    mutating func followRepositoryRoot() async {
        guard let root = await GitCLI.resolveRepositoryRoot(at: URL(fileURLWithPath: repoPath)) else { return }
        move(to: root.path(percentEncoded: false))
    }

    /// The clone opened as `openedPath`.
    mutating func move(to openedPath: String) {
        guard openedPath != repoPath else { return }
        undo()
        previous = store.choice(repoPath: openedPath, remoteName: "origin")
        store.setChoice(.account(accountId), repoPath: openedPath, remoteName: "origin")
        repoPath = openedPath
    }
}
