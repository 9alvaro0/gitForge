import Foundation

extension RepositoryViewModel {
    enum UndoOutcome: Sendable, Equatable {
        /// Undone; the toast that says so.
        case undone(String)
        /// Not applied: the repository changed since, or nothing is on offer.
        case refused(String)
        /// git failed; the entry stays on offer when trying again may work.
        case failed(String)
    }

    /// Runs the undo on offer — only `id`'s, when given (the toast's button).
    /// A local undo holds `isMutating` like any other operation; undoing a
    /// force-push is a push and holds `remoteOperation` instead.
    func performUndo(id: UUID? = nil) async -> UndoOutcome {
        guard let entry = undo.pending, id == nil || entry.id == id else {
            return .refused(UndoRefusal.notOffered.userMessage)
        }
        if entry.isNetwork {
            guard remoteOperation == nil else { return .failed(GitError.busy.userMessage) }
        } else {
            guard !isMutating else { return .failed(GitError.busy.userMessage) }
        }
        guard let taken = undo.take(id: entry.id) else { return .refused(UndoRefusal.notOffered.userMessage) }
        if taken.isNetwork {
            remoteOperation = .pushing
            remoteFailure = nil
        } else {
            commitError = nil
            isMutating = true
        }
        defer {
            if taken.isNetwork { remoteOperation = nil } else { isMutating = false }
        }
        do {
            try await cli.performUndo(taken.operation)
            await refreshAfterUndo(taken)
            return .undone(taken.doneMessage)
        } catch let refusal as UndoRefusal {
            // The state moved on: this undo will never apply. Show the repo as it is.
            await refreshAfterUndo(taken)
            return .refused(refusal.userMessage)
        } catch {
            // A failed push or a git hiccup: keep it on offer.
            undo.restore(taken)
            await refreshAfterUndo(taken)
            return .failed(error.userMessage)
        }
    }

    private func refreshAfterUndo(_ entry: UndoEntry) async {
        if entry.isNetwork {
            await loadRefs()
            await reloadLogIfScopeMoved()
        } else {
            // Refs, status, conflicts and the log: an undo can touch any of them.
            await refreshAfterIntegration()
        }
    }
}
