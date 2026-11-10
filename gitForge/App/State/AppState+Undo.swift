import Foundation

extension AppState {
    /// Runs the active repository's undo — `entryID`'s only, from a toast —
    /// and reports how it went. Shared by the toast's Undo and Edit ▸ Undo.
    func undoInActiveRepository(entryID: UUID? = nil) async {
        guard let viewModel = catalog.activeViewModel else { return }
        switch await viewModel.performUndo(id: entryID) {
        case .undone(let message):
            ui.activeToast = ToastMessage(message: message, kind: .ok)
        case .refused(let message):
            ui.activeToast = ToastMessage(message: message, kind: .warn)
        case .failed(let message):
            ui.activeToast = ToastMessage(message: message, kind: .error)
        }
    }
}
