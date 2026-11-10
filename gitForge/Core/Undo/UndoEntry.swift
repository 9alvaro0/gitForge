import Foundation

/// The inverse of one destructive operation, recorded just before (and
/// right after) it ran. `GitCLI.performUndo(_:)` applies it, checking first
/// that the repository is still where the operation left it.
///
/// History-rewriting operations (amend, reword, squash…) reuse `.reset`
/// or `.moveBranch`: all they need is the tip before and after.
nonisolated enum UndoOperation: Sendable, Equatable {
    /// HEAD (and the branch it is on) back to where it was before a reset.
    case reset(HeadReset)
    /// A branch that isn't checked out, back to its previous tip.
    case moveBranch(name: String, movedTo: String, previous: String)
    /// A deleted local branch, recreated at its tip with its config
    /// (`branch.<name>.*`: upstream, pushRemote, rebase…).
    case deleteBranch(name: String, sha: String, config: [ConfigEntry])
    /// A dropped stash, stored again with its original message.
    case dropStash(sha: String, message: String)
    /// Discarded tracked changes in `paths`, written back from a snapshot.
    case discard(WorktreeRestore)
    /// A force-push: the remote branch back to `previous`, leased on the SHA
    /// we pushed so a push made since by someone else is never overwritten.
    case forcePush(remote: String, branch: String, pushed: String, previous: String)

    nonisolated struct HeadReset: Sendable, Equatable {
        /// The branch HEAD was on; `nil` when it was detached.
        let branch: String?
        let mode: GitCLI.ResetMode
        let previousSha: String
        /// Where the reset left HEAD.
        let resultSha: String
        /// The index and worktree before the reset; `nil` when they were
        /// clean. Brings back what `--mixed` unstaged and what `--hard`
        /// threw away.
        let snapshot: WorkingTreeSnapshot?
    }

    nonisolated struct ConfigEntry: Sendable, Equatable {
        let key: String
        let value: String
    }

    nonisolated struct WorktreeRestore: Sendable, Equatable {
        /// Tree of the tracked files on disk just before the discard
        /// (`WorkingTreeSnapshot.worktree`).
        let snapshot: String
        let paths: [String]
        /// Index entries and worktree diff of `paths` right after the
        /// discard. Undo refuses when they no longer match.
        let fingerprint: String
    }
}

/// The index and the tracked files on disk at one moment, as two trees in
/// the object database (`GitCLI.snapshotWorkingTree`).
nonisolated struct WorkingTreeSnapshot: Sendable, Equatable {
    let index: String
    let worktree: String
}

/// What Edit ▸ Undo and the toast's Undo button offer for a repository.
nonisolated struct UndoEntry: Sendable, Equatable, Identifiable {
    let id = UUID()
    let operation: UndoOperation

    /// The Edit menu item, e.g. "Undo Reset of main".
    var menuTitle: String {
        switch operation {
        case .reset(let reset):
            let target = reset.branch ?? String(reset.resultSha.prefix(7))
            return String(localized: "Undo Reset of \(target)")
        case .moveBranch(let name, _, _):
            return String(localized: "Undo Move of \(name)")
        case .deleteBranch(let name, _, _):
            return String(localized: "Undo Delete of \(name)")
        case .dropStash:
            return String(localized: "Undo Drop Stash")
        case .discard:
            return String(localized: "Undo Discard")
        case .forcePush(let remote, let branch, _, _):
            return String(localized: "Undo Force-Push to \(remote)/\(branch)")
        }
    }

    /// The toast once the undo went through.
    var doneMessage: String {
        switch operation {
        case .reset(let reset):
            let target = reset.branch ?? "HEAD"
            let sha = String(reset.previousSha.prefix(7))
            return String(localized: "\(target) is back at \(sha)")
        case .moveBranch(let name, _, let previous):
            let sha = String(previous.prefix(7))
            return String(localized: "\(name) is back at \(sha)")
        case .deleteBranch(let name, _, _):
            return String(localized: "Restored branch \(name)")
        case .dropStash:
            return String(localized: "Restored the stash")
        case .discard(let restore):
            return restore.paths.count == 1
                ? String(localized: "Restored the discarded changes")
                : String(localized: "Restored the discarded changes in \(restore.paths.count) files")
        case .forcePush(let remote, let branch, _, let previous):
            let sha = String(previous.prefix(7))
            return String(localized: "\(remote)/\(branch) is back at \(sha)")
        }
    }

    /// Talks to a remote: runs as a push, not as a local mutation.
    var isNetwork: Bool {
        if case .forcePush = operation { return true }
        return false
    }
}

/// Why an undo wasn't applied: the repository moved on since the operation,
/// so applying it would land on top of someone else's change.
nonisolated enum UndoRefusal: LocalizedError, Equatable {
    /// The undo on offer is another one (or none): a stale toast button.
    case notOffered
    case headMoved(String)
    case changesSinceReset
    case branchMoved(String)
    case branchCheckedOut(String)
    case branchExists(String)
    case stashAlreadyListed
    case objectMissing
    case filesChanged
    case remoteMoved(String)

    var errorDescription: String? {
        switch self {
        case .notOffered:
            String(localized: "That can no longer be undone.")
        case .headMoved(let target):
            String(localized: "Can't undo the reset: \(target) has moved since.")
        case .changesSinceReset:
            String(localized: "Can't undo the reset: commit, stash or discard the changes you made since.")
        case .branchMoved(let name):
            String(localized: "Can't undo: \(name) has moved since.")
        case .branchCheckedOut(let name):
            String(localized: "Can't undo: \(name) is checked out now.")
        case .branchExists(let name):
            String(localized: "Can't undo: a branch named \(name) exists again.")
        case .stashAlreadyListed:
            String(localized: "That stash is already in the list.")
        case .objectMissing:
            String(localized: "Can't undo: git no longer has those commits.")
        case .filesChanged:
            String(localized: "Can't undo the discard: those files have changed since.")
        case .remoteMoved(let target):
            String(localized: "Can't undo: \(target) has changed since your force-push.")
        }
    }
}
