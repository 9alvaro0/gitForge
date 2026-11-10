import AppKit
import SwiftUI

/// Edit ▸ Undo / Redo. Replaces the standard pair so ⌘Z can also undo the
/// repository's last destructive operation (`UndoStore`); while text is
/// being edited both keep forwarding to the responder chain, as before.
struct EditCommands: Commands {
    /// Plain `let`, as in `RepositoryCommands`.
    let appState: AppState

    var body: some Commands {
        CommandGroup(replacing: .undoRedo) {
            Button(undoTitle) {
                switch UndoMenuRouting.route(editingText: Self.isEditingText,
                                             repositoryUndoOffered: pendingUndo != nil) {
                case .responderChain:
                    _ = NSApp.sendAction(Selector(("undo:")), to: nil, from: nil)
                case .repository:
                    Task { await appState.undoInActiveRepository() }
                }
            }
            .keyboardShortcut("z", modifiers: .command)

            Button("Redo") {
                _ = NSApp.sendAction(Selector(("redo:")), to: nil, from: nil)
            }
            .keyboardShortcut("z", modifiers: [.command, .shift])
        }
    }

    private var pendingUndo: UndoEntry? {
        appState.catalog.activeViewModel?.undo.pending
    }

    /// "Undo Reset of main" while the repository offers one. The title
    /// can't follow the keyboard focus, so with text focused ⌘Z still
    /// undoes typing even though the menu names the repository's undo.
    private var undoTitle: String {
        pendingUndo?.menuTitle ?? String(localized: "Undo")
    }

    /// An editable text view (a field's editor, a text editor) is first
    /// responder in the key window.
    private static var isEditingText: Bool {
        (NSApp.keyWindow?.firstResponder as? NSTextView)?.isEditable ?? false
    }
}
