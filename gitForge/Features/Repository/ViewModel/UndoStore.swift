import Foundation
import Observation

/// The one undo a repository offers: the last destructive operation, until
/// the next mutating operation in that repository replaces or clears it.
/// The toast's Undo button and Edit ▸ Undo (⌘Z) both read it.
///
/// There's no stack on purpose: each entry is checked against the state the
/// operation left, and only the latest one can still match it.
@Observable
@MainActor
final class UndoStore {
    private(set) var pending: UndoEntry?

    /// Offers `operation` (nil offers nothing) and returns its entry.
    @discardableResult
    func record(_ operation: UndoOperation?) -> UndoEntry? {
        pending = operation.map { UndoEntry(operation: $0) }
        return pending
    }

    /// Puts back an entry whose undo failed for a reason that may pass (the
    /// network), so it can be tried again.
    func restore(_ entry: UndoEntry) {
        pending = entry
    }

    /// Another mutating operation started: what was on offer no longer
    /// undoes the latest change.
    func invalidate() {
        pending = nil
    }

    /// Takes the pending entry to run it; with `id`, only if it is that one
    /// (a toast for an older operation must not undo a newer one).
    func take(id: UUID? = nil) -> UndoEntry? {
        guard let entry = pending, id == nil || entry.id == id else { return nil }
        pending = nil
        return entry
    }
}
