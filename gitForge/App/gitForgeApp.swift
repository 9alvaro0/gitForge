import SwiftUI

@main
struct GitForgeApp: App {
    @State private var appState = AppState()
    @State private var updater = Updater()
    @Environment(\.scenePhase) private var scenePhase
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    private static let minWindowSize = CGSize(width: 820, height: 560)

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                // Each sub-store is also injected on its own so features can
                // declare narrow `@Environment(WorkspaceUI.self)` etc.
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
                    // External CLI changes might have happened while the app
                    // was inactive — pulse the active repo so they show up.
                    appState.catalog.activeViewModel?.pokeReactivity()
                }
        }
        .commands {
            FileCommands(appState: appState)
            ViewCommands(appState: appState)
            RepositoryCommands(appState: appState)
            HelpCommands(updater: updater)
        }
    }
}
