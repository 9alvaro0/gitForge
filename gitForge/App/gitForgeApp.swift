import SwiftUI

@main
struct GitForgeApp: App {
    @State private var appState = AppState()
    @Environment(\.scenePhase) private var scenePhase
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    /// Smallest window size that still accommodates the sidebar + main column
    /// + status bar without truncating their content.
    private static let minWindowSize = CGSize(width: 820, height: 560)

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                // Sub-stores exposed independently so features can depend only
                // on what they actually need (e.g. a view that only reads the
                // theme grabs `WorkspaceUI`, not the whole `AppState`).
                .environment(appState.catalog)
                .environment(appState.gitEnvironment)
                .environment(appState.clone)
                .environment(appState.ui)
                .frame(minWidth: Self.minWindowSize.width, minHeight: Self.minWindowSize.height)
                .task { await appState.bootstrap() }
                .onChange(of: scenePhase) { _, newPhase in
                    guard newPhase == .active else { return }
                    if appState.gitEnvironment.gitStatus == .notFound {
                        Task { await appState.gitEnvironment.refreshGitInstallation() }
                    }
                    // Pulse the active repo so external CLI changes show up
                    // as soon as the user comes back to the app.
                    appState.catalog.activeViewModel?.pokeReactivity()
                }
        }
        .commands {
            FileCommands(appState: appState)
            ViewCommands(appState: appState)
            RepositoryCommands(appState: appState)
            HelpCommands()
        }
    }
}
