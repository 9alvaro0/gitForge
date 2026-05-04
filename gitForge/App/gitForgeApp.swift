import SwiftUI

@main
struct gitForgeApp: App {
    @State private var appState = AppState()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .task {
                    await appState.refreshGitInstallation()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active && appState.gitStatus == .notFound {
                        Task { await appState.refreshGitInstallation() }
                    }
                }
        }
        .windowResizability(.contentSize)
    }
}
