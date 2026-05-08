import SwiftUI

/// Top of the view tree. Gates the UI on `gitStatus` (checking · notFound ·
/// available) and hosts the global error alert. The actual app shell — sidebar,
/// content router, command palette, toasts — lives in `App/Shell/ShellView`.
struct RootView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var ui = appState.ui
        Group {
            switch appState.gitEnvironment.gitStatus {
            case .checking:
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .notFound:
                GitNotFoundView()
            case .available:
                ShellView()
            }
        }
        .appTheme(ui.theme)
        .alert(
            ui.presentedError?.title ?? "",
            isPresented: $ui.presentedError.isPresent(),
            presenting: ui.presentedError
        ) { _ in
            // Cancel-role buttons in `.alert` automatically clear the
            // `isPresented` binding, which clears `presentedError` for us.
            Button("OK", role: .cancel) {}
        } message: { error in
            Text(error.message)
        }
    }
}

#Preview("Welcome (no active repo)") {
    RootView()
        .previewAppState(.preview)
        .frame(width: 1200, height: 720)
}

#Preview("Repository active") {
    RootView()
        .previewAppState(.previewWithActive)
        .frame(width: 1280, height: 760)
}

#Preview("Git not found") {
    RootView()
        .previewAppState(.previewMissingGit)
        .frame(width: 1100, height: 720)
}
