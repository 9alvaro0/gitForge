import SwiftUI

/// Asks what to do with the local changes a checkout was refused over —
/// stash them or discard them — and checks out again. On the shell, like the
/// pull's question, so the sidebar, Branches, History and pull requests all
/// get it.
private struct BlockedCheckoutPrompt: ViewModifier {
    @Environment(AppState.self) private var appState

    func body(content: Content) -> some View {
        let viewModel = appState.catalog.activeViewModel
        let blocked = viewModel?.blockedCheckout
        content.confirmationDialog(
            blocked?.title ?? "",
            isPresented: Binding(get: { blocked != nil },
                                 set: { if !$0 { viewModel?.blockedCheckout = nil } }),
            titleVisibility: .visible,
            presenting: blocked
        ) { blocked in
            // Stashing takes Return: it switches without losing anything, so
            // a reflexive press is safe. Discarding needs a deliberate click.
            Button("Stash and Check Out") {
                run { await $0.stashBlockingChangesAndCheckout(blocked) }
            }
            .keyboardShortcut(.defaultAction)
            Button("Discard and Check Out", role: .destructive) {
                run { await $0.discardBlockingChangesAndCheckout(blocked) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { blocked in
            Text(blocked.message)
        }
    }

    private func run(_ action: @escaping (RepositoryViewModel) async -> RepositoryViewModel.CheckoutOutcome) {
        guard let viewModel = appState.catalog.activeViewModel else { return }
        Task { appState.ui.emitToast(for: await action(viewModel)) }
    }
}

extension View {
    func blockedCheckoutPrompt() -> some View {
        modifier(BlockedCheckoutPrompt())
    }
}
