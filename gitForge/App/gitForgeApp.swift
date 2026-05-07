import SwiftUI
import AppKit

@main
struct gitForgeApp: App {
    @State private var appState = AppState()
    @Environment(\.scenePhase) private var scenePhase
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

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

/// Forces `isMovableByWindowBackground = false` on every window the app
/// becomes key on. SwiftUI re-applies its window defaults asynchronously
/// (after focus changes, fullscreen toggles, etc.), so a one-shot fix from
/// `viewDidMoveToWindow` gets clobbered. Listening to `didBecomeKeyNotification`
/// guarantees we win the last write.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Sweep any windows that exist at launch (the WindowGroup's first
        // window is already created by this point).
        for window in NSApp.windows {
            disableBackgroundDrag(window)
        }
        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { notification in
            if let window = notification.object as? NSWindow {
                disableBackgroundDrag(window)
            }
        }
    }
}

private func disableBackgroundDrag(_ window: NSWindow) {
    // Without this, macOS treats every non-interactive region as a window-
    // drag handle, stealing events from internal resize handles (split panes,
    // columns) and from any background area the user clicks on.
    window.isMovableByWindowBackground = false
}
