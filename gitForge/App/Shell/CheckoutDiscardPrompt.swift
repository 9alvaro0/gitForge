import SwiftUI

/// Asks whether to discard the local changes a checkout was refused over and
/// check out again. On the shell, like the pull's question, so the sidebar,
/// Branches, History and pull requests all get it.
private struct CheckoutDiscardPrompt: ViewModifier {
    @Environment(AppState.self) private var appState

    func body(content: Content) -> some View {
        let viewModel = appState.catalog.activeViewModel
        let request = viewModel?.checkoutDiscardRequest
        content.confirmationDialog(
            request?.title ?? "",
            isPresented: Binding(get: { request != nil },
                                 set: { if !$0 { viewModel?.checkoutDiscardRequest = nil } }),
            titleVisibility: .visible,
            presenting: request
        ) { request in
            // Cancel takes Return, as in the staging Discard all: a reflexive
            // press mustn't throw work away.
            Button("Cancel", role: .cancel) {}
                .keyboardShortcut(.defaultAction)
            Button("Discard and Check Out", role: .destructive) {
                Task {
                    guard let viewModel else { return }
                    appState.ui.emitToast(for: await viewModel.discardBlockingChangesAndCheckout(request))
                }
            }
        } message: { request in
            Text(request.message)
        }
    }
}

extension View {
    func checkoutDiscardPrompt() -> some View {
        modifier(CheckoutDiscardPrompt())
    }
}
