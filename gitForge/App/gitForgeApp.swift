import SwiftUI

@main
struct gitForgeApp: App {
    @State private var appState = AppState()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .frame(minWidth: 900, minHeight: 600)
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
            CommandGroup(replacing: .newItem) {
                Button("Open Repository...") {
                    Task { await appState.presentOpenRepositoryPanel() }
                }
                .keyboardShortcut("o", modifiers: .command)

                Button("Close Repository") {
                    appState.closeRepository()
                }
                .keyboardShortcut("w", modifiers: [.command, .shift])
                .disabled(appState.activeRepository == nil)
            }
        }
    }
}
