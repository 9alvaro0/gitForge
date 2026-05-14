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
                    // Resume the cadenced background work the resignActive
                    // handler paused, then nudge the watcher so any external
                    // change while we were away surfaces immediately.
                    appState.catalog.resumeBackgroundWork()
                    appState.catalog.activeViewModel?.resumeBackgroundWork()
                    appState.catalog.activeViewModel?.pokeReactivity(force: true)
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
                    // Stop polling + auto-fetch while the app is in the
                    // background — no point burning battery talking to remotes
                    // for windows the user can't see. The FS watcher stays
                    // armed; macOS suspends its events in background anyway.
                    appState.catalog.pauseBackgroundWork()
                    appState.catalog.activeViewModel?.pauseBackgroundWork()
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
