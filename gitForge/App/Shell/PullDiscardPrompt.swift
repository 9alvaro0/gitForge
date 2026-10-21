import SwiftUI

/// Asks whether to discard the local changes a pull was refused over and
/// pull again. On the shell, like the pull's toasts, so the toolbar, the
/// menu and the palette all get it.
private struct PullDiscardPrompt: ViewModifier {
    @Environment(AppState.self) private var appState

    func body(content: Content) -> some View {
        let viewModel = appState.catalog.activeViewModel
        let request = viewModel?.pullDiscardRequest
        content.confirmationDialog(
            request?.title ?? "",
            isPresented: Binding(get: { request != nil },
                                 set: { if !$0 { viewModel?.pullDiscardRequest = nil } }),
            titleVisibility: .visible,
            presenting: request
        ) { request in
            // Cancel takes Return, as in the staging Discard all: a reflexive
            // press mustn't throw work away.
            Button("Cancel", role: .cancel) {}
                .keyboardShortcut(.defaultAction)
            Button("Discard and Pull", role: .destructive) {
                Task { await viewModel?.discardBlockingChangesAndPull(request) }
            }
        } message: { request in
            Text(request.message)
        }
    }
}

extension View {
    func pullDiscardPrompt() -> some View {
        modifier(PullDiscardPrompt())
    }
}
