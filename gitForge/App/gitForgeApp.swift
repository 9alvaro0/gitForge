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
                    if newPhase == .active && appState.gitStatus == .notFound {
                        Task { await appState.refreshGitInstallation() }
                    }
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
