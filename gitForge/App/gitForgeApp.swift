import SwiftUI

@main
struct gitForgeApp: App {
    @State private var appState = AppState()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .frame(minWidth: 820, minHeight: 560)
                .task {
                    await appState.bootstrap()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    guard newPhase == .active else { return }
                    if appState.gitStatus == .notFound {
                        Task { await appState.refreshGitInstallation() }
                    }
                    // Pulse the active repo so external CLI changes show up
                    // as soon as the user comes back to the app.
                    appState.activeViewModel?.pokeReactivity()
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
