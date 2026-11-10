import SwiftUI

/// Shows the output of a git hook that stopped a commit or a `--continue`,
/// with Retry. On the shell, like the checkout prompt, so the composer and
/// the conflict resolver both get it.
private struct HookFailurePrompt: ViewModifier {
    @Environment(AppState.self) private var appState

    func body(content: Content) -> some View {
        let viewModel = appState.catalog.activeViewModel
        content.sheet(item: Binding(get: { viewModel?.hookFailure },
                                    set: { if $0 == nil { viewModel?.hookFailure = nil } })) { failure in
            HookFailureSheet(
                failure: failure,
                onRetry: { retry(failure, skipHooks: false) },
                onCommitWithoutHooks: { retry(failure, skipHooks: true) },
                onClose: { viewModel?.hookFailure = nil }
            )
        }
    }

    private func retry(_ failure: HookFailure, skipHooks: Bool) {
        guard let viewModel = appState.catalog.activeViewModel else { return }
        Task { await viewModel.retry(failure, skipHooks: skipHooks) }
    }
}

extension View {
    func hookFailurePrompt() -> some View {
        modifier(HookFailurePrompt())
    }
}
