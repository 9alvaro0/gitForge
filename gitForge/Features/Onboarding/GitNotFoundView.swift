import SwiftUI

struct GitNotFoundView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.appTheme) private var theme
    @State private var isInstalling = false

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.xhuge) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 56))
                .foregroundStyle(theme.palette.warn.gradient)
                .symbolRenderingMode(.hierarchical)

            VStack(spacing: DesignTokens.Spacing.lg) {
                Text("Git is required")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("gitForge needs the `git` command-line tool. Install the Xcode Command Line Tools to continue.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(theme.palette.fg3)
                    .frame(maxWidth: 440)
            }

            HStack(spacing: DesignTokens.Spacing.xl) {
                Button {
                    installCommandLineTools()
                } label: {
                    Label("Install Command Line Tools", systemImage: "arrow.down.circle")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isInstalling)

                Button("Recheck") {
                    Task { await appState.refreshGitInstallation() }
                }
                .controlSize(.large)
            }
        }
        .padding(48)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func installCommandLineTools() {
        isInstalling = true
        Task {
            await Task.detached {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
                process.arguments = ["--install"]
                try? process.run()
                process.waitUntilExit()
            }.value
            isInstalling = false
            await appState.refreshGitInstallation()
        }
    }
}

#Preview {
    GitNotFoundView()
        .environment(AppState())
        .frame(width: 720, height: 480)
}
