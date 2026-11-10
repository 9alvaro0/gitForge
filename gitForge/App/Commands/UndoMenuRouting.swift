import Foundation

/// Where Edit ▸ Undo (⌘Z) goes. Text being edited keeps its own undo, so
/// ⌘Z in the commit message never rewinds a reset; elsewhere it undoes the
/// repository's last destructive operation while one is offered.
nonisolated enum UndoMenuRouting: Equatable {
    /// Forward `undo:` along the responder chain (text fields, editors).
    case responderChain
    case repository

    static func route(editingText: Bool, repositoryUndoOffered: Bool) -> UndoMenuRouting {
        if editingText || !repositoryUndoOffered { return .responderChain }
        return .repository
    }
}
