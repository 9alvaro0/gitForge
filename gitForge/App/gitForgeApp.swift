import SwiftUI
import AppKit

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
                .environment(appState.profiles)
                .frame(minWidth: Self.minWindowSize.width, minHeight: Self.minWindowSize.height)
                .task { await appState.bootstrap() }
                .onChange(of: scenePhase) { _, newPhase in
                    guard newPhase == .active else { return }
                    if appState.gitEnvironment.gitStatus == .notFound {
                        Task { await appState.gitEnvironment.refreshGitInstallation() }
                    }
                }
                // AppKit's didBecomeActive fires more reliably than SwiftUI's
                // scenePhase on macOS (single-window scenes don't always
                // re-emit `.active` on Cmd-Tab returns) and didBecomeKey
                // covers focus moving between our own windows. We force-poke
                // here so the watcher's cooldown can't drop a user-visible
                // refresh.
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    appState.catalog.activeViewModel?.pokeReactivity(force: true)
                }
                .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
                    appState.catalog.activeViewModel?.pokeReactivity(force: true)
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
