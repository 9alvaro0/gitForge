import SwiftUI

/// Top of the view tree. Gates the UI on `gitStatus` (checking · notFound ·
/// available) and hosts the global error alert. The actual app shell — sidebar,
/// content router, command palette, toasts — lives in `App/Shell/ShellView`.
struct RootView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
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
        .appTheme(appState.ui.theme)
        .alert(appState.ui.presentedError?.title ?? "",
               isPresented: presentedErrorBinding) {
            Button("OK", role: .cancel) { appState.ui.presentedError = nil }
        } message: {
            Text(appState.ui.presentedError?.message ?? "")
        }
    }

    private var presentedErrorBinding: Binding<Bool> {
        Binding(
            get: { appState.ui.presentedError != nil },
            set: { if !$0 { appState.ui.presentedError = nil } }
        )
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
