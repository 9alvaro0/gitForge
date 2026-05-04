import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Group {
            switch appState.gitStatus {
            case .checking:
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .notFound:
                GitNotFoundView()
            case .available:
                MainNavigationView()
            }
        }
        .alert(
            appState.presentedError?.title ?? "",
            isPresented: presentedErrorBinding
        ) {
            Button("OK", role: .cancel) {
                appState.presentedError = nil
            }
        } message: {
            Text(appState.presentedError?.message ?? "")
        }
    }

    private var presentedErrorBinding: Binding<Bool> {
        Binding(
            get: { appState.presentedError != nil },
            set: { newValue in
                if !newValue {
                    appState.presentedError = nil
                }
            }
        )
    }
}

private struct MainNavigationView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        } detail: {
            if let repo = appState.activeRepository {
                RepositoryView(repository: repo)
            } else {
                WelcomeView()
            }
        }
    }
}

#Preview("Welcome (no active repo)") {
    RootView()
        .environment(AppState.preview)
        .frame(width: 1100, height: 720)
}

#Preview("Repository active") {
    RootView()
        .environment(AppState.previewWithActive)
        .frame(width: 1100, height: 720)
}

#Preview("Git not found") {
    RootView()
        .environment(AppState.previewMissingGit)
        .frame(width: 1100, height: 720)
}
