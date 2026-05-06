import SwiftUI

/// Confirmation alert wired to `AppState.discardAllConfirmVisible`. The Repository
/// menu sets the flag; this modifier shows the destructive prompt and runs the
/// discard against every file in the working copy on confirmation.
struct DiscardAllAlertModifier: ViewModifier {
    @Bindable var appState: AppState
    let viewModel: RepositoryViewModel

    func body(content: Content) -> some View {
        content.alert(
            "Discard all changes?",
            isPresented: $appState.discardAllConfirmVisible
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Discard All", role: .destructive) {
                let files = viewModel.status.files
                guard !files.isEmpty else { return }
                Task { await viewModel.discardChanges(files) }
            }
        } message: {
            let count = viewModel.status.files.count
            Text("This will discard \(count) uncommitted change\(count == 1 ? "" : "s") and remove untracked files. This cannot be undone.")
        }
    }
}
