import SwiftUI
import AppKit

/// Process entry point. Unit tests run *inside* the app (it is their test
/// host), so launching the real `GitForgeApp` there meant every test run
/// bootstrapped the full app: it reopened the user's last repository, started
/// the status poller over every recent repo, armed the watchers and the
/// auto-fetcher (real `git fetch` on the user's repos), and let Sparkle check
/// for updates — all while competing with the tests for the main actor.
/// Under XCTest an empty app is launched instead.
@main
enum AppLauncher {
    static func main() {
        if isRunningTests {
            TestHostApp.main()
        } else {
            GitForgeApp.main()
        }
    }

    /// Set by Xcode / xcodebuild when the process hosts a test bundle.
    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment.keys.contains { $0.hasPrefix("XCTest") }
    }
}

/// Inert app used as the test host: no window, no bootstrap, no background work.
private struct TestHostApp: App {
    var body: some Scene {
        Settings { EmptyView() }
    }
}

struct GitForgeApp: App {
    @State private var appState = AppState()
    @State private var updater = Updater()
    @Environment(\.scenePhase) private var scenePhase
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    private static let minWindowSize = CGSize(width: 1100, height: 700)

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
                .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { note in
                    // Only a real window coming forward is a signal that the
                    // user may have changed things elsewhere. Sheets, alerts
                    // and panels (open panel, popovers) become key too, and
                    // each one used to trigger a full refresh on dismissal.
                    guard let window = note.object as? NSWindow,
                          !(window is NSPanel),
                          window.sheetParent == nil else { return }
                    appState.catalog.activeViewModel?.pokeReactivity(force: true)
                }
        }
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            FileCommands(appState: appState)
            ViewCommands(appState: appState)
            RepositoryCommands(appState: appState)
            HelpCommands(updater: updater)
        }
    }
}
